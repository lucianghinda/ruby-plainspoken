# Ruby and Rails rules, with both sides of each one

Every rule here has a case where it applies and a case where it does not. Read the pair before deciding. If a rule and the repository's own instructions disagree, the repository wins.

## Repository fit

### Follow the pattern the application already uses

**Applies.** The application has three services that all take their inputs in `initialize`, expose one `call`, return a result object, and raise a named error on failure. A fourth service of the same kind is asked for.

```ruby
class RefundPayment
  def initialize(payment:, amount:)
    @payment = payment
    @amount = amount
  end

  def call
    raise RefundNotAllowed, "payment #{@payment.id} is not settled" unless @payment.settled?

    Refund.create!(payment: @payment, amount: @amount)
  end
end
```

Match the construction, the public method name, the return, the failure behaviour, the naming, and the test layout. Read the existing tests too — a service pattern includes how it is tested.

**Does not apply.** The nearby services each carry their own copy of the same discount calculation, and the defect you were asked to fix is in that calculation. Copying the pattern would copy the defect into a fourth place. Fix the shared calculation once, put it where all four can use it, and say in one sentence that the existing duplication is the reason you did not follow the pattern.

### Fix the cause, not the caller that reported it

**Applies.** A report says one endpoint returns stale totals. `Order#total` is missing a reload after a line item changes, and six callers use it. Fix `Order#total`.

**Does not apply.** The shared method is correct and one caller passes it the wrong argument. Fix that caller. Changing a correct shared method to accommodate one wrong call site breaks the other five.

## Objects

### Do not create an object that only forwards

**Applies — remove it.**

```ruby
class UserNotifier
  def initialize(user)
    @user = user
  end

  def notify
    UserMailer.welcome(@user).deliver_later
  end
end

UserNotifier.new(user).notify
```

One caller, one forwarded call, no decision of its own. Call the mailer:

```ruby
UserMailer.welcome(user).deliver_later
```

**Does not apply — keep it.** The object translates an external system and isolates its failures.

```ruby
class PaymentGateway
  Unavailable = Class.new(StandardError)

  def charge(customer_id:, amount_cents:, currency:)
    response = Stripe::Charge.create(customer: customer_id, amount: amount_cents, currency:)
    Receipt.new(reference: response.id, charged_at: Time.zone.at(response.created))
  rescue Stripe::APIConnectionError => e
    raise Unavailable, e.message
  end
end
```

The rest of the application never sees a `Stripe::` constant and never handles a `Stripe::` error. That is a boundary, and it stays even with one caller today.

### Do not create a concern for one include

**Applies — remove it.** A concern with one `included` block, one method and one including class is a class with an extra file. Put the method on the class.

**Does not apply — keep it.** Three models need the same soft-delete behaviour with the same column and the same default scope. One concern, three includes, one place to change it.

### Do not add an interface for a second implementation nobody has asked for

**Applies — remove it.** There is one storage backend, one adapter class, one abstract base class and one registry that maps a single key to that one adapter. Delete the base class and the registry; keep the adapter.

**Does not apply — keep it.** The application already runs two backends in production, selected by configuration. Two implementations exist, so the interface names something real.

### Split objects by what they know, not by when they run

**Applies — merge them.** `OrderImporter` reads a CSV, `OrderRowValidator` checks each row, `OrderRowSaver` writes it. All three know the column order and the date format, so a new column means three edits. Put the row format in one object; the steps are its private methods.

**Does not apply — keep them split.** `OrderCsv` knows the file format and yields plain hashes. `OrderWriter` knows the models and the transaction. Each one can change without the other. That is a split by knowledge, and it stays.

## Methods and signatures

### Keyword arguments for inputs a caller could confuse

**Applies.**

```ruby
def schedule(worker, venue, start_time, end_time, notify)
```

Two identifiers of different kinds, two times of the same kind, and a boolean that says nothing at the call site. `schedule(w, v, a, b, true)` is unreadable and a swapped pair of times is a silent bug. Use required keywords:

```ruby
def schedule(worker:, venue:, starts_at:, ends_at:, notify:)
```

**Does not apply.** One obvious input, or an interface that is called positionally.

```ruby
def include?(shift)          # one obvious input, keep it positional
def <=>(other)              # Ruby calls this positionally
def each(&block)            # Enumerable's contract
def perform(order_id)       # Active Job passes arguments positionally
```

Do not add keywords to a method Ruby, Rails or an existing caller calls positionally.

### Do not turn parameters into an options hash

**Applies — remove it.** `def create(attributes = {})` followed by `attributes.fetch(:name)`, `attributes[:email]` and a raise when a key is missing rebuilds keyword arguments by hand, with worse errors. Declare the keywords.

**Does not apply — keep it.** The method genuinely passes an open set of attributes straight through to `update!` or to a query. A hash is the shape of the thing.

### Do not add a flag so the caller decides what the method can decide

**Applies — remove it.**

```ruby
def send_receipt(order, resend: false)
  return if order.receipt_sent? && !resend
  ...
end
```

Every caller now has to know what `resend:` means. If the second send is always safe, send it; if it is never wanted, check inside. The method knows which.

**Does not apply — keep it.** Two callers genuinely want different behaviour and the difference is part of the contract: `deliver_now` and `deliver_later` exist for that reason.

### Keep a short expression inline when a method would only rename it

**Applies — inline it.**

```ruby
def full_name
  "#{first_name} #{last_name}"
end

def positive_amount
  amount.positive?
end
```

`positive_amount` says nothing `amount.positive?` does not. Write `amount.positive?` at the one call site.

**Does not apply — keep the method.**

```ruby
def bookable?
  published? && starts_at > 24.hours.from_now && !cancelled?
end
```

The name states the rule. Callers rely on `bookable?` and not on its three parts, and the rule can change in one place. A one-line predicate that carries domain meaning is worth keeping even at one call site.

## Comments

### Do not describe readable code

**Applies — delete them.**

```ruby
# Set the user's name
user.name = name

# Loop through the orders
orders.each do |order|
  # Charge the order
  charge(order)
end
```

**Does not apply — keep it.** The reason cannot be recovered from the code, the names, the types or the tests.

```ruby
# The vendor API rejects a page size above 200 with a 500, not a 4xx, so this
# cannot be raised without also handling the misreported error.
PAGE_SIZE = 200
```

Also keep a comment that records a deliberate limit with a known ceiling, and name what would trigger the upgrade:

```ruby
# Scans every shift in the window; fine to a few thousand, needs an index-backed
# query above that.
```

Do not put a ticket number in a comment because the work happened under that ticket. Reference a ticket only when it records a specific decision a future reader needs, or when the code exists because of an incident.

## Errors

### Let the operation succeed instead of raising

**Applies.** Three controllers each wrap `Subscription.find(id).cancel!` in `rescue ActiveRecord::RecordNotFound` and `rescue AlreadyCancelled`. Cancelling what is already cancelled, or already gone, is the state the caller wanted. Make `cancel!` a no-op in both cases, or use `find_by` and return, and delete the three rescues.

**Does not apply.** `charge!` on a payment that fails at the gateway must raise. A silent return would record an order nobody paid for. Keep the raise, and handle it once at the boundary that owns the response.

### Handle a real error in one place

`rescue_from` in a controller, `retry_on` and `discard_on` in a job, or one boundary object that translates a vendor's errors. Do not repeat the same `rescue` at every call site.

## Sorbet

### Do not name a shape you use once

**Applies — inline it.**

```ruby
Row = T.type_alias { T::Hash[Symbol, T.untyped] }

sig { params(row: Row).returns(String) }
def label(row)
```

`Row` names nothing a reader does not already see. Write the type at the use:

```ruby
sig { params(row: T::Hash[Symbol, T.untyped]).returns(String) }
def label(row)
```

**Does not apply — keep the alias.** It gives a complex type a real domain name, and removing it would hide that name from every signature that uses it.

```ruby
RateTable = T.type_alias { T::Hash[Symbol, T::Array[T::Hash[Symbol, Numeric]]] }
```

Keep it also when a public contract other code already depends on refers to the alias.

### Do not reach for `T.untyped` or `T.must` to make a signature pass

Give the real type. `T.must` is a claim that the value cannot be nil — check that it holds on the path you traced, and if it does not, handle nil instead.

## Values and immutability

### `Data.define` for a small named value

**Applies.** Ruby 3.2 or newer, the fields are the identity, nothing changes after construction, and callers depend on the names.

```ruby
Money = Data.define(:amount_cents, :currency)
BookingWindow = Data.define(:starts_at, :ends_at)
```

**Does not apply, case 1 — the Ruby version.** On Ruby 3.1 or older `Data.define` does not exist. Check `.ruby-version`, `Gemfile`, or the gemspec's `required_ruby_version` before using it. Use whatever the application already uses for values — often `Struct.new(..., keyword_init: true)` — and do not add a gem to backport `Data`.

**Does not apply, case 2 — it is an entity.** Identity survives while the fields change. A `Booking` that gets rescheduled and cancelled is not a value. Use a normal object, or the Active Record model, that protects its own state.

**Does not apply, case 3 — there is no meaningful name.** Three unrelated fields returned together from one method, used once, named `Result`. Return the hash.

### Do not write the boilerplate `Data` replaces

If the value qualifies, `Data.define(:a, :b)` replaces the initializer, the readers, `==`, `hash`, `eql?`, `to_h`, `deconstruct_keys` and `inspect`. Do not hand-write them.

## Collections and return shapes

### A named object instead of a hash, when the names are the contract

**Applies.** Several callers read `result[:total]`, `result[:currency]` and `result[:breakdown]`, and a typo in a key fails at the caller rather than at the method.

```ruby
Quote = Data.define(:total, :currency, :breakdown)
```

**Does not apply.** One caller consumes the hash on the next line and the field meaning is obvious there. Keep the hash; the object would add a concept that lives for two lines.

### An enumerable object instead of an array, when callers keep asking the same questions

**Applies.** Four call sites each write `shifts.select(&:unfilled?).sum(&:hours)` or a variant of it.

```ruby
class ShiftSchedule
  include Enumerable

  def initialize(shifts)
    @shifts = shifts
  end

  def each(&) = @shifts.each(&)

  def unfilled_hours = @shifts.select(&:unfilled?).sum(&:hours)

  def covers?(time) = @shifts.any? { |shift| shift.covers?(time) }
end
```

Expose iteration and the questions that are actually asked. Do not mirror every `Array` method.

**Does not apply.** The caller iterates the collection once and asks it nothing. Return the array, or return the Active Record relation so the caller can still add to the query.

### Do not wrap an Active Record relation

Returning `Shift.where(venue:)` lets the caller chain another scope, page it, or count it in the database. Wrapping it in an object that exposes `each` throws that away and usually loads every row into Ruby. Wrap it only when the wrapper genuinely adds named behaviour, and then keep the relation reachable.

## Rails

### Use the framework facility that already meets the requirement

**Applies — use Rails.**

| Asked for | Rails already has it |
|---|---|
| A value must be present and unique | `validates :x, presence: true, uniqueness: true`, plus a unique index in a migration |
| Run this later, retry on failure | Active Job with `retry_on` |
| Do something after a record is saved | A callback, or the caller doing it explicitly — but not a new observer layer |
| Fetch the associated records without an N+1 query | `preload` or `includes` on the relation |
| Cache a computed value | `Rails.cache.fetch` |
| Store an enumerated state | `enum` on the model |
| Wrap several writes so they succeed or fail together | `ActiveRecord::Base.transaction` |
| Serialize a model for an API | The serializer the application already uses |

Do not add a repository layer over Active Record, a queue wrapper over Active Job, or a validation mechanism next to Active Model validations, when the framework facility covers the request.

**Does not apply — write a plain Ruby object.** The work has several steps, its own inputs, its own failure modes, and no model that naturally owns it: taking a payment, then writing a receipt, then notifying two parties. That is not a model concern and not a callback. Give it a specific name — what it does, not `Manager` or `Handler` — and put it wherever this application keeps such objects.

### Do not add a callback that hides a step from its caller

A callback is right for something that must be true of every save, wherever it comes from. A callback that fires network calls, sends email, or depends on state only one controller sets belongs in the caller, where a reader can see it.

### Database integrity lives in the database

A model validation is not a constraint. When the requirement is "this can never be null" or "this pair is unique", write the migration as well as the validation. Uniqueness enforced only in Ruby loses a race.

## Safety that a smaller change may not remove

Keep all of these even when the change would be shorter without them:

- **Validation and authorization.** Removing a permission check is not a simplification. If a check looks redundant, prove it by finding the other check that covers the same path, and name it.
- **Database integrity.** Constraints, uniqueness indexes, foreign keys, not-null. Dropping a constraint to make a migration pass is data loss waiting to happen.
- **Transaction boundaries.** Two writes that must both happen stay in one transaction. Do not widen a transaction over a network call either.
- **Untrusted input.** Parameter filtering, strong parameters, escaping, and anything that stops SQL or shell interpolation.
- **Accessibility.** Labels, roles, focus handling and text alternatives in views are behaviour, not decoration.
- **Error handling that prevents data loss.** A rescue that retries or records a failure is not noise.
- **Existing tests.** Do not delete or weaken a test to make a change pass. If a test now asserts the wrong thing, say so and say why, then change it deliberately.

`rescue => e` followed by nothing is not error handling. Either handle the error, or let it raise.

## Tests

### Leave one focused check

**Applies.** The change adds a branch, a loop, a parser or a safety path. Write the smallest test that fails if that logic breaks, in the framework the repository already uses.

Minitest repository:

```ruby
class BookingWindowTest < ActiveSupport::TestCase
  test "rejects a window that ends before it starts" do
    assert_raises(ArgumentError) { BookingWindow.new(starts_at: 2.days.from_now, ends_at: 1.day.from_now) }
  end
end
```

RSpec repository:

```ruby
RSpec.describe BookingWindow do
  it "rejects a window that ends before it starts" do
    expect { described_class.new(starts_at: 2.days.from_now, ends_at: 1.day.from_now) }
      .to raise_error(ArgumentError)
  end
end
```

Look at how the tests next to yours set up data — fixtures, factories, or plain objects — and do that.

**Does not apply.** A one-line change with no branch and no new behaviour. Do not add a test that asserts the language works.

### Never add a second test framework

If the repository runs Minitest, write Minitest. If it runs RSpec, write RSpec. Do not add RSpec to a Minitest repository for one test, and do not leave a script with `raise unless ...` in place of a test the repository could run.

### Assert the behaviour, not the implementation

A test that stubs the method under test, or asserts that a private method was called, passes when the behaviour is broken. Assert what the caller can observe.

Before finishing a test written alongside a bug fix, ask one question of each assertion: would this still pass if the bug were back? If yes, the assertion is not testing the fix.
