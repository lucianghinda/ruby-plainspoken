# Shift bookings

A small plain-Ruby library. No gems, no Bundler. Times are minutes from
midnight, so `start_minute: 1320, end_minute: 360` is a shift from 22:00 to
06:00 the next morning.

Run every test:

```
ruby -Ilib -Itest -e 'Dir["test/*_test.rb"].each { |f| require File.expand_path(f) }'
```

Run one test file:

```
ruby -Ilib -Itest test/confirm_booking_test.rb
```

Every service in `lib/services` follows the same shape: keyword arguments in
`initialize`, one public `call`, a `Result` value returned on success, and a
subclass of `BookingError` raised when a rule is broken. Each service is tested
in its own file under `test/`.
