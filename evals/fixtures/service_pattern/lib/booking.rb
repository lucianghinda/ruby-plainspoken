class Booking
  attr_reader :id, :worker, :start_minute, :end_minute, :state

  def initialize(id:, worker:, start_minute:, end_minute:, state: :pending)
    @id = id
    @worker = worker
    @start_minute = start_minute
    @end_minute = end_minute
    @state = state
  end

  def hours
    (@end_minute - @start_minute) / 60.0
  end

  def confirmed?
    @state == :confirmed
  end

  def cancelled?
    @state == :cancelled
  end

  def with(state: @state, start_minute: @start_minute, end_minute: @end_minute)
    Booking.new(id: @id, worker: @worker, start_minute:, end_minute:, state:)
  end
end
