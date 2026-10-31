class TimesheetsController < ApplicationController
  before_action :set_timesheet, only: [:show, :update]

  def index
    @timesheets = Timesheet.where(venue: current_user.managed_venues).order(:week_starting)
  end

  def show
  end

  def update
    authorize @timesheet, :update?

    if params[:approve].present?
      @timesheet.approve!(current_user)
      redirect_to @timesheet, notice: "Timesheet approved."
    elsif @timesheet.update(timesheet_params)
      redirect_to @timesheet, notice: "Timesheet updated."
    else
      render :show, status: :unprocessable_entity
    end
  rescue Timesheet::AlreadyApproved => e
    redirect_to @timesheet, alert: e.message
  end

  private

  def set_timesheet
    @timesheet = Timesheet.find(params[:id])
  end

  def timesheet_params
    params.require(:timesheet).permit(:hours, :week_starting)
  end
end
