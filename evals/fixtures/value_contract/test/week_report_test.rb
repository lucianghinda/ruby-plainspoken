require "test_helper"
require "week_report"

class WeekReportTest < Minitest::Test
  include TimesheetBuilder

  def timesheets
    [
      build_timesheet(worker: "amy", hours: 10.0, night_hours: 4.0),
      build_timesheet(worker: "ben", hours: 10.0, night_hours: 0.0),
      build_timesheet(worker: "amy", hours: 5.0, night_hours: 5.0)
    ]
  end

  def test_adds_up_every_hour
    assert_in_delta 25.0, WeekReport.new(timesheets).total_hours
  end

  def test_adds_up_the_night_hours
    assert_in_delta 9.0, WeekReport.new(timesheets).night_hours
  end

  def test_names_the_workers_who_worked_nights
    assert_equal ["amy"], WeekReport.new(timesheets).workers_on_nights
  end

  def test_reports_the_share_of_hours_worked_at_night
    assert_in_delta 0.36, WeekReport.new(timesheets).night_share
  end
end
