require "test_helper"

class PublishShiftTest < ActiveSupport::TestCase
  test "publishes the shift and records who did it" do
    shift = shifts(:draft_evening)

    PublishShift.new(shift:, published_by: users(:manager)).call

    assert shift.reload.published?
    assert_equal "published", AuditEntry.last.action
  end

  test "refuses to publish a shift with no pay rate" do
    shift = shifts(:draft_evening)
    shift.update_column(:pay_rate_pence, nil)

    assert_raises(PublishShift::NotReady) do
      PublishShift.new(shift:, published_by: users(:manager)).call
    end
  end
end
