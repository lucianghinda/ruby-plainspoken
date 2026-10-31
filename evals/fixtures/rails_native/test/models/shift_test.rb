require "test_helper"

class ShiftTest < ActiveSupport::TestCase
  test "rejects a shift that ends before it starts" do
    shift = Shift.new(venue: venues(:brighton), starts_at: 2.days.from_now, ends_at: 1.day.from_now, pay_rate_pence: 1200)

    assert_not shift.valid?
    assert_includes shift.errors[:ends_at], "must be after the start"
  end

  test "reports its length in hours" do
    shift = shifts(:evening)

    assert_in_delta 8.0, shift.hours
  end
end
