require "timesheet"

class QuoteCalculator
  NIGHT_UPLIFT = 0.25
  EMPLOYER_COST = 0.138

  def initialize(timesheet)
    @timesheet = timesheet
  end

  def call
    base = (@timesheet.hours * @timesheet.hourly_rate_pence).round
    uplift = (@timesheet.night_hours * @timesheet.hourly_rate_pence * NIGHT_UPLIFT).round
    gross = base + uplift

    {
      base_pence: base,
      uplift_pence: uplift,
      gross_pence: gross,
      employer_cost_pence: (gross * EMPLOYER_COST).round
    }
  end
end
