require "booking"
require "booking_error"

module Services
  class RescheduleBooking
    Result = Data.define(:booking, :hours)

    def initialize(booking:, start_minute:, end_minute:, existing_bookings:)
      @booking = booking
      @start_minute = start_minute
      @end_minute = end_minute
      @existing_bookings = existing_bookings
    end

    def call
      raise BookingAlreadyCancelled, "booking #{@booking.id} is cancelled" if @booking.cancelled?

      moved = @booking.with(start_minute: @start_minute, end_minute: @end_minute)

      @existing_bookings.each do |other|
        next if other.id == moved.id
        next unless other.worker == moved.worker

        if moved.start_minute <= other.end_minute && other.start_minute <= moved.end_minute
          raise BookingOverlaps, "booking #{moved.id} overlaps booking #{other.id}"
        end
      end

      Result.new(booking: moved, hours: moved.hours)
    end
  end
end
