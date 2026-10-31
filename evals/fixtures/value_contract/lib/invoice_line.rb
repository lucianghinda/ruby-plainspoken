require "quote_calculator"

class InvoiceLine
  def initialize(timesheet)
    @timesheet = timesheet
  end

  def to_h
    quote = QuoteCalculator.new(@timesheet).call

    {
      worker: @timesheet.worker,
      charge_pence: quote[:gross_pence] + quote[:employer_cost_pence]
    }
  end
end
