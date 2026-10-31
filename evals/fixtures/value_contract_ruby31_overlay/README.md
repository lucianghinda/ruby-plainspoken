# Ruby 3.1 overlay for the value_contract fixture

Copied over `evals/fixtures/value_contract` by the case that has to choose a
value shape on a Ruby version without `Data.define`. It changes two things:

- `.ruby-version` becomes 3.1.4, so `Data.define` is not available.
- `lib/tax_band.rb` appears, so the project has an established value shape
  (`Struct.new(..., keyword_init: true)`) for the agent to follow.

This is a separate directory, not a subdirectory of the fixture, so that the
base fixture stays exactly what a Ruby 3.4 project looks like.
