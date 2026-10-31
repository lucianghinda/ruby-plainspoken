require "test_helper"
require "payroll_export"

class PayrollExportTest < Minitest::Test
  include TimesheetBuilder

  def test_exports_one_row_per_timesheet
    rows = PayrollExport.new([build_timesheet(worker: "amy"), build_timesheet(worker: "ben")]).rows

    assert_equal [["amy", 12_000, 1_656], ["ben", 12_000, 1_656]], rows
  end
end
