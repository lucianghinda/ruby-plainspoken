require "test_helper"
require "services/cancel_booking"

class CancelBookingTest < Minitest::Test
  include BookingBuilder

  def test_cancels_a_pending_booking
    result = Services::CancelBooking.new(booking: build_booking).call

    assert result.booking.cancelled?
  end

  def test_refuses_to_cancel_twice
    assert_raises(BookingAlreadyCancelled) do
      Services::CancelBooking.new(booking: build_booking(state: :cancelled)).call
    end
  end
end
