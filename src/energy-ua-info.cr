require "http/client"
require "json"
require "option_parser"
require "colorize"

require "./schedule_payload"

def format_duration(duration : Time::Span)
  hours = duration.hours
  minutes = duration.minutes

  "#{hours}:#{"%02d" % minutes}"
end

def print_periods(periods : Periods, title : String)
  puts

  puts "Відключення #{title}".colorize.underline
  puts

  if periods.empty?
    puts "Немає даних"
    return
  end

  without_electricity = periods.sum(&.length)

  without_electricity_formatted = "-#{format_duration(without_electricity)}".colorize.red
  with_electricity_formatted = "+#{format_duration(24.hours - without_electricity)}".colorize.green

  puts "#{without_electricity_formatted} #{with_electricity_formatted}"

  puts "Періоди відключень на #{title}:"

  periods.each do |period|
    duration = period.length

    duration_formatted = format_duration(duration).colorize.bold
    time_from_formatted = period.time_from.in(SCHEDULE_TIME_ZONE).to_s("%H:%M").colorize.bold
    time_to_formatted = period.time_to.in(SCHEDULE_TIME_ZONE).to_s("%H:%M").colorize.bold

    puts "  - з #{time_from_formatted} до #{time_to_formatted}, тривалість #{duration_formatted}"
  end
end

def print_timeline(periods : Periods, time : Time = Time.local(SCHEDULE_TIME_ZONE))
  # 96 blocks, one per 15 minutes
  timeline = Array(String | Colorize::Object(String)).new(96, "")

  separator = "│"
  block = "█"

  now = Time.local(SCHEDULE_TIME_ZONE)

  96.times do |i|
    block_time = time.at_beginning_of_day + (i * 15).minutes
    in_outage = periods.any? { |period| block_time >= period.time_from && block_time < period.time_to }
    is_now = same_date?(time, now) && (now.hour * 4 + (now.minute // 15)) == i

    if is_now
      timeline[i] = (in_outage ? block.colorize(:light_red) : block.colorize(:light_green))
    elsif in_outage
      timeline[i] = block.colorize(:red)
    else
      timeline[i] = block.colorize(:green)
    end
  end

  # Print hour labels with separators
  hour_labels = separator + (0..23).join(separator) { |hour| " %02d " % hour } + separator
  puts hour_labels

  # Print timeline with separators for each hour
  timeline_line = String.build do |io|
    24.times do |hour|
      io << separator

      4.times do |quarter|
        io << timeline[hour * 4 + quarter]
      end
    end

    io << separator
  end

  puts timeline_line
end

def has_electricity?(periods : Periods, time : Time = Time.local(SCHEDULE_TIME_ZONE)) : Bool
  !periods.any?(&.time_range.includes?(time))
end

def next_turn_off(periods : Periods) : Period?
  next_turn_offs = periods.select { |period| period.time_from > Time.local(SCHEDULE_TIME_ZONE) }

  return unless next_turn_offs.present?

  next_turn_offs.min_by(&.time_from)
end

def next_turn_on(periods : Periods) : Period?
  next_turn_ons = periods.select { |period| period.time_to > Time.local(SCHEDULE_TIME_ZONE) }

  return unless next_turn_ons.present?

  next_turn_ons.min_by(&.time_to)
end

def same_date?(time : Time, other : Time = Time.local(SCHEDULE_TIME_ZONE)) : Bool
  time.year == other.year &&
    time.month == other.month &&
    time.day == other.day
end

option_parser = OptionParser.parse do |parser|
  parser.banner = <<-USAGE
    Використання: energy-ua-info CITY GROUP SUBGROUP

    Де:
      CITY - назва міста (наприклад, kyiv, lviv, kharkiv)
      GROUP - номер групи (наприклад, 1, 2, 3)
      SUBGROUP - номер підгрупи (наприклад, 1, 2)

    Приклад:
      energy-ua-info kyiv 1 1

    Отримає інформацію про відключення електроенергії для Києва, групи 1, підгрупи 1.
    USAGE

  parser.on("-h", "--help", "Показати це повідомлення") do
    puts parser
    exit
  end
end

city = ARGV[0]? || (STDERR.puts option_parser.to_s; exit(1))
group = ARGV[1]? || (STDERR.puts option_parser.to_s; exit(1))
subgroup = ARGV[2]? || (STDERR.puts option_parser.to_s; exit(1))

url = "https://#{city}.energy-ua.info/grupa/#{group}-#{subgroup}"

begin
  response = HTTP::Client.get(url)

  unless response.success?
    puts "Не вдалося отримати інформацію по відключеннях для міста #{city} та групи #{group}.#{subgroup}."
    puts "Перевірте правильність введених даних."
    puts "URL: #{url}"

    puts "HTTP статус: #{response.status_code}"
    exit 1
  end
rescue ex
  puts "Помилка при спробі підключення до #{url}: #{ex.message}"
  exit 1
end

title_regex = /<h1>(.*)<\/h1>/

if m = response.body.match(title_regex)
  puts m[1].colorize.bold.underline
end
puts url
puts

puts "Поточний час: #{Time.local(SCHEDULE_TIME_ZONE).to_s("%Y-%m-%d %H:%M")}"
puts "#{group} група (#{subgroup} підгрупа)"

begin
  schedule = SchedulePayload.new(response.body)
rescue ex
  STDERR.puts "Не вдалося прочитати графік відключень: #{ex.message}"
  exit 1
end

periods = schedule.today

if has_electricity?(periods) && (next_turn_off = next_turn_off(periods))
  time_to_turn_of = next_turn_off.time_from - Time.local(SCHEDULE_TIME_ZONE)
  puts "Наступне відключення заплановане через: #{format_duration(time_to_turn_of).colorize.bold}"
end

if !has_electricity?(periods) && (next_turn_on = next_turn_on(periods))
  time_to_turn_on = next_turn_on.time_to - Time.local(SCHEDULE_TIME_ZONE)
  puts "До увімкнення залишилось почекати: #{format_duration(time_to_turn_on).colorize.bold}"
end

print_periods(periods, "сьогодні")
puts
print_timeline(periods, schedule.today_date)

if schedule.tomorrow_available?
  print_periods(schedule.tomorrow, "завтра")
  puts
  print_timeline(schedule.tomorrow, schedule.tomorrow_date)
else
  puts
  puts "Графік на завтра ще недоступний"
end
