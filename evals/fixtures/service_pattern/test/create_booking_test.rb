require "test_helper"
require "services/create_booking"

class CreateBookingTest < Minitest::Test
  include BookingBuilder

  def test_creates_a_booking_with_no_overlap
    result = Services::CreateBooking.new(
      id: 7,
      worker: "amy",
      start_minute: 540,
      end_minute: 1020,
      existing_bookings: []
    ).call

    assert_equal 7, result.booking.id
    assert_in_delta 8.0, result.hours
  end

  def test_rejects_a_booking_that_overlaps_the_same_worker
    other = build_booking(id: 2, start_minute: 900, end_minute: 1200)

    assert_raises(BookingOverlaps) do
      Services::CreateBooking.new(
        id: 7,
        worker: "amy",
        start_minute: 540,
        end_minute: 1020,
        existing_bookings: [other]
      ).call
    end
  end
end
