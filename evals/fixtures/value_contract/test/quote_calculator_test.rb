require "test_helper"
require "quote_calculator"

class QuoteCalculatorTest < Minitest::Test
  include TimesheetBuilder

  def test_pays_the_hourly_rate_for_every_hour
    quote = QuoteCalculator.new(build_timesheet(hours: 10.0, hourly_rate_pence: 1200)).call

    assert_equal 12_000, quote[:base_pence]
    assert_equal 0, quote[:uplift_pence]
    assert_equal 12_000, quote[:gross_pence]
  end

  def test_adds_an_uplift_for_night_hours
    quote = QuoteCalculator.new(build_timesheet(hours: 10.0, hourly_rate_pence: 1200, night_hours: 4.0)).call

    assert_equal 1_200, quote[:uplift_pence]
    assert_equal 13_200, quote[:gross_pence]
  end

  def test_adds_the_employer_cost_on_top_of_gross_pay
    quote = QuoteCalculator.new(build_timesheet(hours: 10.0, hourly_rate_pence: 1200)).call

    assert_equal 1_656, quote[:employer_cost_pence]
  end
end
