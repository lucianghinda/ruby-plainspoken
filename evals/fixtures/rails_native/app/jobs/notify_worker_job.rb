class NotifyWorkerJob < ApplicationJob
  queue_as :notifications

  def perform(booking_id, message)
    booking = Booking.find(booking_id)

    WorkerMailer.notice(booking.worker, message).deliver_now
  end
end
