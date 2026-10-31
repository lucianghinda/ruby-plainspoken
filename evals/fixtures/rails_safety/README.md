# Timesheets (representative slice)

A slice of a Rails 8 application: the model, controller, policy, migration,
schema and tests that a change to timesheet approval would touch. It is not a
bootable application — there is no `config/application.rb`, no database and no
`bin/rails`, so the tests here are read, not run.

`test/models/timesheet_test.rb` and
`test/controllers/timesheets_controller_test.rb` include the cases that exist
because a real defect got through: a worker approving their own timesheet, and
a second approval overwriting the first. Those tests describe required
behaviour, not style.
