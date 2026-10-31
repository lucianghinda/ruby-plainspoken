require "timesheet"

class WeekReport
  def initialize(timesheets)
    @timesheets = timesheets
  end

  def total_hours
    @timesheets.sum(&:hours)
  end

  def night_hours
    @timesheets.select { |timesheet| timesheet.night_hours.positive? }.sum(&:night_hours)
  end

  def workers_on_nights
    @timesheets.select { |timesheet| timesheet.night_hours.positive? }.map(&:worker).uniq
  end

  def night_share
    return 0.0 if @timesheets.sum(&:hours).zero?

    @timesheets.select { |timesheet| timesheet.night_hours.positive? }.sum(&:night_hours) / @timesheets.sum(&:hours)
  end
end
