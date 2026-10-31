require "booking"

module Reports
  class WeeklySummary
    def initialize(bookings:)
      @bookings = bookings
    end

    def call
      confirmed = @bookings.select(&:confirmed?)

      {
        bookings: confirmed.length,
        hours: confirmed.sum(&:hours)
      }
    end
  end
end
