class Timesheet
  attr_reader :id, :worker, :hours, :hourly_rate_pence, :night_hours

  def initialize(id:, worker:, hours:, hourly_rate_pence:, night_hours: 0)
    @id = id
    @worker = worker
    @hours = hours
    @hourly_rate_pence = hourly_rate_pence
    @night_hours = night_hours
  end
end
