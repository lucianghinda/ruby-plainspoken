require "minitest/autorun"
require "booking"
require "booking_error"

module BookingBuilder
  def build_booking(id: 1, worker: "amy", start_minute: 540, end_minute: 1020, state: :pending)
    Booking.new(id:, worker:, start_minute:, end_minute:, state:)
  end
end
