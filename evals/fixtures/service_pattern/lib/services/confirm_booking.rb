require "booking"
require "booking_error"

module Services
  class ConfirmBooking
    Result = Data.define(:booking, :hours)

    def initialize(booking:, existing_bookings:)
      @booking = booking
      @existing_bookings = existing_bookings
    end

    def call
      raise BookingNotConfirmable, "booking #{@booking.id} is cancelled" if @booking.cancelled?

      @existing_bookings.each do |other|
        next if other.id == @booking.id
        next unless other.worker == @booking.worker

        if @booking.start_minute <= other.end_minute && other.start_minute <= @booking.end_minute
          raise BookingOverlaps, "booking #{@booking.id} overlaps booking #{other.id}"
        end
      end

      confirmed = @booking.with(state: :confirmed)
      Result.new(booking: confirmed, hours: confirmed.hours)
    end
  end
end
