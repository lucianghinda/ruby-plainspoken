# Payroll quotes

A small plain-Ruby library. No gems, no Bundler.

Run every test:

```
ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

`QuoteCalculator#call` produces the pay figures for one timesheet. Three
callers read those figures: `Payslip`, `InvoiceLine` and `PayrollExport`.

`WeekReport` answers questions about a list of timesheets.
