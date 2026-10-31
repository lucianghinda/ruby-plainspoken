require "test_helper"

class TimesheetTest < ActiveSupport::TestCase
  test "refuses a second approval" do
    timesheet = timesheets(:approved_week)

    assert_raises(Timesheet::AlreadyApproved) do
      timesheet.approve!(users(:other_manager))
    end
  end

  test "rejects more hours than a week holds" do
    timesheet = timesheets(:submitted_week)
    timesheet.hours = 200

    assert_not timesheet.valid?
  end

  test "rejects a second timesheet for the same worker, venue and week" do
    existing = timesheets(:submitted_week)
    duplicate = Timesheet.new(
      worker: existing.worker,
      venue: existing.venue,
      week_starting: existing.week_starting,
      hours: 10
    )

    assert_not duplicate.valid?
  end
end
