require "booking"
require "booking_error"

module Services
  class CancelBooking
    Result = Data.define(:booking, :hours)

    def initialize(booking:)
      @booking = booking
    end

    def call
      raise BookingAlreadyCancelled, "booking #{@booking.id} is already cancelled" if @booking.cancelled?

      cancelled = @booking.with(state: :cancelled)
      Result.new(booking: cancelled, hours: cancelled.hours)
    end
  end
end
