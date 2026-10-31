require "quote_calculator"

class Payslip
  def initialize(timesheet)
    @timesheet = timesheet
  end

  def lines
    quote = QuoteCalculator.new(@timesheet).call

    [
      "Basic pay: #{pounds(quote[:base_pence])}",
      "Night uplift: #{pounds(quote[:uplift_pence])}",
      "Gross pay: #{pounds(quote[:gross_pence])}"
    ]
  end

  private

  def pounds(pence)
    format("£%.2f", pence / 100.0)
  end
end
