require "minitest/autorun"
require "timesheet"

module TimesheetBuilder
  def build_timesheet(id: 1, worker: "amy", hours: 10.0, hourly_rate_pence: 1200, night_hours: 0)
    Timesheet.new(id:, worker:, hours:, hourly_rate_pence:, night_hours:)
  end
end
