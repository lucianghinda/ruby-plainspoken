require "test_helper"
require "reports/weekly_summary"

class WeeklySummaryTest < Minitest::Test
  include BookingBuilder

  def test_counts_only_confirmed_bookings
    bookings = [
      build_booking(id: 1, start_minute: 540, end_minute: 1020, state: :confirmed),
      build_booking(id: 2, start_minute: 540, end_minute: 1020, state: :pending)
    ]

    summary = Reports::WeeklySummary.new(bookings:).call

    assert_equal 1, summary[:bookings]
    assert_in_delta 8.0, summary[:hours]
  end

  def test_adds_the_hours_of_every_confirmed_booking
    bookings = [
      build_booking(id: 1, start_minute: 540, end_minute: 1020, state: :confirmed),
      build_booking(id: 2, start_minute: 600, end_minute: 780, state: :confirmed)
    ]

    summary = Reports::WeeklySummary.new(bookings:).call

    assert_equal 2, summary[:bookings]
    assert_in_delta 11.0, summary[:hours]
  end
end
