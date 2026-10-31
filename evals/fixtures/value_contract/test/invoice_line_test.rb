require "test_helper"
require "invoice_line"

class InvoiceLineTest < Minitest::Test
  include TimesheetBuilder

  def test_charges_gross_pay_plus_the_employer_cost
    line = InvoiceLine.new(build_timesheet(worker: "amy")).to_h

    assert_equal({ worker: "amy", charge_pence: 13_656 }, line)
  end
end
