require "test_helper"

class TimesheetsControllerTest < ActionDispatch::IntegrationTest
  test "a worker cannot approve their own timesheet" do
    sign_in users(:worker_amy)

    assert_raises(Pundit::NotAuthorizedError) do
      patch timesheet_path(timesheets(:submitted_week)), params: { approve: "1" }
    end
  end

  test "a manager of another venue cannot update the timesheet" do
    sign_in users(:unrelated_manager)

    assert_raises(Pundit::NotAuthorizedError) do
      patch timesheet_path(timesheets(:submitted_week)), params: { timesheet: { hours: 5 } }
    end
  end

  test "an approved timesheet keeps the state a request tries to set directly" do
    sign_in users(:manager)

    patch timesheet_path(timesheets(:submitted_week)), params: { timesheet: { hours: 5, state: "approved" } }

    assert_equal "submitted", timesheets(:submitted_week).reload.state
  end
end
