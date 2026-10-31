require "test_helper"
require "services/confirm_booking"

class ConfirmBookingTest < Minitest::Test
  include BookingBuilder

  def test_confirms_a_booking_with_no_overlap
    booking = build_booking(id: 1, start_minute: 540, end_minute: 1020)
    other = build_booking(id: 2, start_minute: 1080, end_minute: 1200)

    result = Services::ConfirmBooking.new(booking:, existing_bookings: [other]).call

    assert result.booking.confirmed?
    assert_in_delta 8.0, result.hours
  end

  def test_rejects_a_booking_that_overlaps_the_same_worker
    booking = build_booking(id: 1, start_minute: 540, end_minute: 1020)
    other = build_booking(id: 2, start_minute: 900, end_minute: 1200)

    error = assert_raises(BookingOverlaps) do
      Services::ConfirmBooking.new(booking:, existing_bookings: [other]).call
    end

    assert_includes error.message, "overlaps booking 2"
  end

  def test_refuses_to_confirm_a_cancelled_booking
    booking = build_booking(state: :cancelled)

    assert_raises(BookingNotConfirmable) do
      Services::ConfirmBooking.new(booking:, existing_bookings: []).call
    end
  end
end
