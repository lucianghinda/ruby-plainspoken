require "test_helper"
require "payslip"

class PayslipTest < Minitest::Test
  include TimesheetBuilder

  def test_shows_basic_night_and_gross_pay
    lines = Payslip.new(build_timesheet(hours: 10.0, hourly_rate_pence: 1200, night_hours: 4.0)).lines

    assert_equal ["Basic pay: £120.00", "Night uplift: £12.00", "Gross pay: £132.00"], lines
  end
end
