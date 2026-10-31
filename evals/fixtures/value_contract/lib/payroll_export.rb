require "quote_calculator"

class PayrollExport
  def initialize(timesheets)
    @timesheets = timesheets
  end

  def rows
    @timesheets.map do |timesheet|
      quote = QuoteCalculator.new(timesheet).call

      [timesheet.worker, quote[:gross_pence], quote[:employer_cost_pence]]
    end
  end
end
