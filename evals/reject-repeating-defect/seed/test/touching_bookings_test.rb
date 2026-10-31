require "test_helper"
require "services/confirm_booking"
require "services/create_booking"
require "services/reschedule_booking"

class TouchingBookingsTest < Minitest::Test
  include BookingBuilder

  def test_confirming_allows_a_booking_that_starts_when_another_ends
    booking = build_booking(id: 1, start_minute: 1020, end_minute: 1200)
    other = build_booking(id: 2, start_minute: 540, end_minute: 1020)

    result = Services::ConfirmBooking.new(booking:, existing_bookings: [other]).call

    assert result.booking.confirmed?
  end

  def test_creating_allows_a_booking_that_ends_when_another_starts
    other = build_booking(id: 2, start_minute: 1020, end_minute: 1200)

    result = Services::CreateBooking.new(
      id: 1,
      worker: "amy",
      start_minute: 540,
      end_minute: 1020,
      existing_bookings: [other]
    ).call

    assert_equal 1, result.booking.id
  end

  def test_rescheduling_allows_a_booking_that_starts_when_another_ends
    booking = build_booking(id: 1, start_minute: 540, end_minute: 700)
    other = build_booking(id: 2, start_minute: 540, end_minute: 1020)

    result = Services::RescheduleBooking.new(
      booking:,
      start_minute: 1020,
      end_minute: 1200,
      existing_bookings: [booking, other]
    ).call

    assert_equal 1020, result.booking.start_minute
  end
end
