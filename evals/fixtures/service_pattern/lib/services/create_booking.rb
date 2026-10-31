require "booking"
require "booking_error"

module Services
  class CreateBooking
    Result = Data.define(:booking, :hours)

    def initialize(id:, worker:, start_minute:, end_minute:, existing_bookings:)
      @id = id
      @worker = worker
      @start_minute = start_minute
      @end_minute = end_minute
      @existing_bookings = existing_bookings
    end

    def call
      booking = Booking.new(
        id: @id,
        worker: @worker,
        start_minute: @start_minute,
        end_minute: @end_minute
      )

      @existing_bookings.each do |other|
        next unless other.worker == booking.worker

        if booking.start_minute <= other.end_minute && other.start_minute <= booking.end_minute
          raise BookingOverlaps, "booking #{booking.id} overlaps booking #{other.id}"
        end
      end

      Result.new(booking:, hours: booking.hours)
    end
  end
end
