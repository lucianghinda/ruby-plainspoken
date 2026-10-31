class Shift < ApplicationRecord
  belongs_to :venue
  has_many :bookings, dependent: :destroy
  has_many :workers, through: :bookings

  enum :state, { draft: "draft", published: "published", cancelled: "cancelled" }

  validates :starts_at, :ends_at, :pay_rate_pence, presence: true
  validates :pay_rate_pence, numericality: { greater_than: 0 }
  validate :ends_after_it_starts

  scope :upcoming, -> { where(starts_at: Time.current..) }
  scope :for_venue, ->(venue) { where(venue:) }

  def hours
    (ends_at - starts_at) / 1.hour
  end

  private

  def ends_after_it_starts
    return if starts_at.blank? || ends_at.blank?
    return if ends_at > starts_at

    errors.add(:ends_at, "must be after the start")
  end
end
