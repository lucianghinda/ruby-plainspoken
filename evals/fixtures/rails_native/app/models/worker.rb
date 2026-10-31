class Worker < ApplicationRecord
  has_many :bookings, dependent: :destroy
  has_many :shifts, through: :bookings

  validates :name, presence: true
  validates :email, presence: true, uniqueness: true
end
