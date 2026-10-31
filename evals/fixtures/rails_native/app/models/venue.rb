class Venue < ApplicationRecord
  has_many :shifts, dependent: :restrict_with_error

  validates :name, presence: true
  validates :time_zone, presence: true
end
