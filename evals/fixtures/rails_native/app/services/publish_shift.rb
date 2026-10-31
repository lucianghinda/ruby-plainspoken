class PublishShift
  NotReady = Class.new(StandardError)

  def initialize(shift:, published_by:)
    @shift = shift
    @published_by = published_by
  end

  def call
    raise NotReady, "shift #{@shift.id} has no pay rate" if @shift.pay_rate_pence.blank?

    ActiveRecord::Base.transaction do
      @shift.update!(state: :published, published_at: Time.current)
      AuditEntry.create!(subject: @shift, actor: @published_by, action: "published")
    end

    @shift
  end
end
