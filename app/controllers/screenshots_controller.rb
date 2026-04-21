# frozen_string_literal: true

class ScreenshotsController < ApplicationController
  before_action :set_page, only: %i[new create]
  before_action :set_screenshot, only: %i[show edit update destroy]

  def show
    @screenshot_image = @screenshot.primary_image
    @annotations = @screenshot.annotations.includes(:user, annotation_comments: [ :user, :api_key ]).order(:created_at)
    @annotations = @annotations.where(status: params[:status]) if params[:status].in?(%w[open resolved])
  end

  def new
    @screenshot = @page.screenshots.build
  end

  def create
    image_param = params.dig(:screenshot, :image)
    title = screenshot_params[:title]

    @screenshot = if image_param
      Screenshot.create_with_image!(
        page: @page, title: title,
        io: image_param.tempfile,
        filename: image_param.original_filename,
        content_type: image_param.content_type
      )
    else
      @page.screenshots.create!(title: title)
    end

    redirect_to screenshot_path(@screenshot), notice: "Screenshot uploaded."
  rescue ActiveRecord::RecordInvalid => e
    @screenshot = e.record.is_a?(Screenshot) ? e.record : @page.screenshots.build(screenshot_params.except(:image))
    render :new, status: :unprocessable_entity
  end

  def edit
  end

  def update
    image_param = params.dig(:screenshot, :image)

    ActiveRecord::Base.transaction do
      @screenshot.update!(screenshot_params.except(:image))
      attach_replacement_image!(image_param) if image_param
    end

    redirect_to screenshot_path(@screenshot), notice: "Screenshot updated."
  rescue ActiveRecord::RecordInvalid
    render :edit, status: :unprocessable_entity
  end

  def destroy
    page = @page
    @screenshot.destroy
    redirect_to page_path(page), notice: "Screenshot deleted."
  end

  private

  def set_page
    @page = Page.find(params[:page_id])
    @project = Current.user.projects.find(@page.project_id)
  end

  def set_screenshot
    @screenshot = Screenshot.find(params[:id])
    @page = @screenshot.page
    @project = Current.user.projects.find(@page.project_id)
  end

  def screenshot_params
    params.require(:screenshot).permit(:title, :image)
  end

  # Route a form-supplied image replacement through the primary ScreenshotImage
  # so the new blob is what readers render. Resets dimension metadata + enqueues
  # re-analysis so Screenshot#status ends up :ready after the job finishes.
  def attach_replacement_image!(image_param)
    si = @screenshot.primary_image || @screenshot.screenshot_images.create!(viewport: :desktop)
    si.image.attach(image_param)
    si.update!(status: :pending, width: nil, height: nil)
    ScreenshotDimensionJob.perform_later(si)
  end
end
