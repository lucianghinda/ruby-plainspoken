class CancellationsController < ApplicationController
  before_action :set_shift

  def create
    @shift.update!(state: :cancelled)

    redirect_to venue_shift_path(@shift.venue, @shift), notice: "Shift cancelled."
  end

  private

  def set_shift
    @shift = Shift.for_venue(current_venue).find(params[:shift_id])
  end
end
