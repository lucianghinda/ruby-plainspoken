require "test_helper"
require "services/reschedule_booking"

class RescheduleBookingTest < Minitest::Test
  include BookingBuilder

  def test_moves_a_booking
    booking = build_booking(id: 1, start_minute: 540, end_minute: 1020)

    result = Services::RescheduleBooking.new(
      booking:,
      start_minute: 600,
      end_minute: 1080,
      existing_bookings: [booking]
    ).call

    assert_equal 600, result.booking.start_minute
    assert_in_delta 8.0, result.hours
  end

  def test_rejects_a_move_that_overlaps_the_same_worker
    booking = build_booking(id: 1, start_minute: 540, end_minute: 1020)
    other = build_booking(id: 2, start_minute: 1080, end_minute: 1260)

    assert_raises(BookingOverlaps) do
      Services::RescheduleBooking.new(
        booking:,
        start_minute: 1100,
        end_minute: 1200,
        existing_bookings: [booking, other]
      ).call
    end
  end
end
