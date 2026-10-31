# Shiftwork (representative slice)

A slice of a Rails 8 application: the models, jobs, controllers, services,
routes, schema and tests that a change in this area would touch. It is not a
bootable application — there is no `config/application.rb`, no database and no
`bin/rails`, so the tests here are read, not run.

Rails version, gems and the database shape are the real ones. Check
`Gemfile` before assuming a gem is available, and `db/schema.rb` before
assuming a column or an index exists.

Multi-step work that no model owns lives in `app/services`, one class per
operation, named after what it does. `app/services/publish_shift.rb` is the
example to follow.
