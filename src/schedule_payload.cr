require "json"

SCHEDULE_TIME_ZONE = Time::Location.load("Europe/Kyiv")

class Period
  getter time_from : Time
  getter time_to : Time
  getter status : String

  def initialize(@time_from, @time_to, @status)
  end

  def length : Time::Span
    time_to - time_from
  end

  def time_range : Range(Time, Time)
    time_from...time_to
  end
end

alias Periods = Array(Period)

class SchedulePayload
  # <script id="schedulePayload" type="application/json">
  #   {
  #     "today": [
  #       {"from": 630, "to": 960, "status": "red"},
  #       {"from": 1260, "to": 1440, "status": "red"}
  #     ],
  #     "tomorrow": [],
  #     "tomorrowAvailable": false,
  #     "currentTime": 1795166440,
  #     "dates": {
  #       "today": "20.11.2026",
  #       "tomorrow": "21.11.2026"
  #     },
  #     "nextEventTimestamp": 1795183200,
  #     "isCurrentlyOff": true,
  #     "isEmergency": false
  #   }
  # </script>
  SCRIPT_REGEX = /<script\b[^>]*\bid\s*=\s*["']schedulePayload["'][^>]*>(.*?)<\/script\s*>/m

  getter today : Periods
  getter tomorrow : Periods
  getter? tomorrow_available : Bool
  getter today_date : Time
  getter tomorrow_date : Time

  def initialize(html : String)
    match = html.match(SCRIPT_REGEX)
    raise "Не знайдено schedulePayload" unless match

    payload = JSON.parse(match[1])
    @today_date = Time.parse(payload["dates"]["today"].as_s, "%d.%m.%Y", SCHEDULE_TIME_ZONE)
    @tomorrow_date = Time.parse(payload["dates"]["tomorrow"].as_s, "%d.%m.%Y", SCHEDULE_TIME_ZONE)
    @today = parse_periods(payload["today"], today_date)
    @tomorrow = parse_periods(payload["tomorrow"], tomorrow_date)
    @tomorrow_available = payload["tomorrowAvailable"].as_bool
  end

  private def parse_periods(data : JSON::Any, date : Time) : Periods
    data.as_a.map do |period|
      Period.new(date + period["from"].as_i.minutes,
        date + period["to"].as_i.minutes, period["status"].as_s)
    end
  end
end
