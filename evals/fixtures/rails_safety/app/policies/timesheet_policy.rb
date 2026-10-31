class TimesheetPolicy
  def initialize(user, timesheet)
    @user = user
    @timesheet = timesheet
  end

  def update?
    return false if @timesheet.worker.user_id == @user.id

    @user.manages?(@timesheet.venue)
  end
end
