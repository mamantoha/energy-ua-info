require "http/client"
require "json"
require "option_parser"
require "colorize"

class Period
  include JSON::Serializable

  getter id : Int32?

  getter day : Int32 | String

  getter grupa : String?  # Lviv
  getter cherga : String? # Kharkiv

  @[JSON::Field(converter: Time::EpochConverter)]
  getter time_from : Time

  @[JSON::Field(converter: Time::EpochConverter)]
  getter time_to : Time

  getter status : String

  def groupa_or_cherga : String
    grupa || cherga || ""
  end

  def length : Time::Span
    time_to - time_from
  end

  def time_range : Range(Time, Time)
    time_from...time_to
  end
end

alias Periods = Array(Period)

def format_duration(duration : Time::Span)
  hours = duration.hours
  minutes = duration.minutes

  "#{hours}:#{"%02d" % minutes}"
end

def print_periods(periods : Periods, title : String)
  puts

  if periods.empty?
    puts "Немає даних"
    exit 1
  end

  puts "Відключення #{title}".colorize.underline

  without_electricity = periods.sum(&.length)

  without_electricity_formatted = "-#{format_duration(without_electricity)}".colorize.red
  with_electricity_formatted = "+#{format_duration(24.hours - without_electricity)}".colorize.green

  puts "#{without_electricity_formatted} #{with_electricity_formatted}"

  puts
  puts "Періоди відключень на #{title}:"

  periods.each do |period|
    duration = period.length

    duration_formatted = format_duration(duration).colorize.bold
    time_from_formatted = period.time_from.to_local.to_s("%H:%M").colorize.bold
    time_to_formatted = period.time_to.to_local.to_s("%H:%M").colorize.bold

    puts "  - з #{time_from_formatted} до #{time_to_formatted}, тривалість #{duration_formatted}"
  end
end

def print_timeline(periods : Periods)
  # 96 blocks, one per 15 minutes
  timeline = Array(String | Colorize::Object(String)).new(96, "")
  now = Time.local
  periods_ranges = periods.map(&.time_range)

  separator = "│"
  block = "█"

  96.times do |i|
    block_time = now.at_beginning_of_day + (i * 15).minutes
    in_outage = periods.any? { |period| block_time >= period.time_from && block_time < period.time_to }
    is_now = (now.hour * 4 + (now.minute // 15)) == i

    if is_now
      timeline[i] = (in_outage ? block.colorize(:light_red) : block.colorize(:light_green))
    elsif in_outage
      timeline[i] = block.colorize(:red)
    else
      timeline[i] = block.colorize(:green)
    end
  end

  # Print hour labels with separators
  hour_labels = separator + (0..23).join(separator) { |h| " %02d " % h } + separator
  puts hour_labels

  # Print timeline with separators for each hour
  timeline_line = String.build do |io|
    24.times do |h|
      io << separator

      4.times do |q|
        io << timeline[h * 4 + q]
      end
    end

    io << separator
  end

  puts timeline_line
end

def has_electricity?(periods : Periods, time : Time = Time.local) : Bool
  !periods.any?(&.time_range.includes?(time))
end

def next_turn_off(periods : Periods) : Period?
  next_turn_offs = periods.select { |period| period.time_from > Time.local }

  return unless next_turn_offs.present?

  next_turn_offs.min_by(&.time_from)
end

def next_turn_on(periods : Periods) : Period?
  next_turn_ons = periods.select { |period| period.time_to > Time.local }

  return unless next_turn_ons.present?

  next_turn_ons.min_by(&.time_to)
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

title_regex = /<h1 class="main_header">(.*)<\/h1>/

if m = response.body.match(title_regex)
  puts m[1].colorize.bold.underline
end
puts url
puts

puts "Поточний час: #{Time.local.to_s("%Y-%m-%d %H:%M")}"
puts "#{group} група (#{subgroup} підгрупа)"

# const periods = [{"id":2662,"day":26,"grupa":"6.1","time_from":1769400000,"time_to":1769409000,"status":"red"},{"id":2663,"day":26,"grupa":"6.1","time_from":1769421600,"time_to":1769434200,"status":"red"}];
periods_regex = /const periods = (\[.*\]);/

# const tomorrowPeriods = Object.values({"2637":{"from":"09:00","to":"12:30","grupa":"6.1","day":27,"status":"red","time_from":1769497200,"time_to":1769509800,"duration":"3:30 \u0433\u043e\u0434."},"2638":{"from":"19:30","to":"22:00","grupa":"6.1","day":27,"status":"red","time_from":1769535000,"time_to":1769544000,"duration":"2:30 \u0433\u043e\u0434."}});
tomorrow_regex = /const tomorrowPeriods = Object\.values\((\{.*\})\);/

if m = response.body.match(periods_regex)
  periods = Periods.from_json(m[1])

  if has_electricity?(periods) && (next_turn_off = next_turn_off(periods))
    time_to_turn_of = next_turn_off.time_from - Time.local

    puts "Наступне відключення заплановане через: #{format_duration(time_to_turn_of).colorize.bold}"
  end

  if !has_electricity?(periods) && (next_turn_on = next_turn_on(periods))
    time_to_turn_on = next_turn_on.time_to - Time.local
    puts "До увімкнення залишилось почекати: #{format_duration(time_to_turn_on).colorize.bold}"
  end

  print_periods(periods, "сьогодні")
  puts
  print_timeline(periods)
end

if m = response.body.match(tomorrow_regex)
  tomorrow_periods = JSON.parse(m[1]).as_h.map do |_, period_data|
    Period.from_json(period_data.to_json)
  end

  print_periods(tomorrow_periods, "завтра")
end
