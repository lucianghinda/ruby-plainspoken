class Booking < ApplicationRecord
  belongs_to :shift
  belongs_to :worker

  enum :state, { pending: "pending", confirmed: "confirmed", cancelled: "cancelled" }

  validates :worker_id, uniqueness: { scope: :shift_id }
end
