class Timesheet < ApplicationRecord
  belongs_to :worker
  belongs_to :venue
  belongs_to :approved_by, class_name: "User", optional: true

  enum :state, { submitted: "submitted", approved: "approved", rejected: "rejected" }

  validates :week_starting, :hours, presence: true
  validates :hours, numericality: { greater_than: 0, less_than_or_equal_to: 168 }
  validates :worker_id, uniqueness: { scope: [:venue_id, :week_starting] }

  def approve!(approver)
    raise AlreadyApproved, "timesheet #{id} is already approved" if approved?

    update!(state: :approved, approved_by: approver, approved_at: Time.current)
  end

  AlreadyApproved = Class.new(StandardError)
end
