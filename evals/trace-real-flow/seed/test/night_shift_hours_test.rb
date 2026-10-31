require "test_helper"
require "services/confirm_booking"
require "reports/weekly_summary"

class NightShiftHoursTest < Minitest::Test
  include BookingBuilder

  def test_a_night_shift_reports_the_hours_it_actually_covers
    booking = build_booking(id: 1, start_minute: 1320, end_minute: 360)

    result = Services::ConfirmBooking.new(booking:, existing_bookings: []).call

    assert_in_delta 8.0, result.hours
  end

  def test_the_weekly_summary_adds_night_shift_hours_the_same_way
    bookings = [build_booking(id: 1, start_minute: 1320, end_minute: 360, state: :confirmed)]

    summary = Reports::WeeklySummary.new(bookings:).call

    assert_in_delta 8.0, summary[:hours]
  end
end
