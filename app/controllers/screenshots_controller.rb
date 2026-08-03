# frozen_string_literal: true

class ScreenshotsController < ApplicationController
  before_action :set_page, only: %i[new create]
  before_action :set_screenshot, only: %i[show edit update destroy]

  def show
    viewport = validated_workspace_viewport(@screenshot, params[:viewport])
    status = params[:status] if Annotation.statuses.key?(params[:status])

    redirect_to page_workspace_path_for(@screenshot, viewport: viewport, status: status)
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

    redirect_to page_workspace_path_for(@screenshot), notice: "Screenshot uploaded."
  rescue ActiveRecord::RecordInvalid => e
    @screenshot = recover_invalid_screenshot(e)
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

    redirect_to page_workspace_path_for(@screenshot), notice: "Screenshot updated."
  rescue ActiveRecord::RecordInvalid => e
    @screenshot = recover_invalid_screenshot(e)
    render :edit, status: :unprocessable_entity
  end

  def destroy
    page = @page
    project = @project

    destination, notice = page.with_lock do
      @screenshot.destroy!

      if (remaining_screenshot = page.screenshots.recent_first.first)
        [ page_workspace_path_for(remaining_screenshot), "Screenshot deleted." ]
      else
        page.destroy!
        [ project_path(project), "Last version deleted. Page removed." ]
      end
    end

    redirect_to destination, notice: notice
  end

  private

  def set_page
    # Match set_screenshot's scope: allow project members (not just owners)
    # to create screenshots on pages they can access. A pre-PR-3 asymmetry
    # left members able to view but not upload — fixed here.
    @page = Page.joins(project: :project_memberships)
                .where(project_memberships: { user_id: Current.user.id })
                .find(params[:page_id])
    @project = @page.project
  end

  def set_screenshot
    # Scope the initial lookup through the user's projects (including those
    # they're a member of, not just owner) so an attacker probing IDs gets a
    # clean 404 at the query level instead of row-read + authz-raise.
    @screenshot = Screenshot.joins(page: { project: :project_memberships })
                            .where(project_memberships: { user_id: Current.user.id })
                            .find(params[:id])
    @page = @screenshot.page
    @project = @page.project
  end

  def screenshot_params
    params.require(:screenshot).permit(:title, :image)
  end

  # When upload validation fails on ScreenshotImage (e.g. GIF or oversized
  # image), the RecordInvalid carries the ScreenshotImage, not the Screenshot
  # — so _form.html.erb's @screenshot.errors would be empty and the user sees
  # a 422 with no explanation. Copy the blob-level errors onto Screenshot so
  # they render.
  def recover_invalid_screenshot(invalid_error)
    if invalid_error.record.is_a?(Screenshot)
      invalid_error.record
    else
      screenshot = @screenshot || @page.screenshots.build(screenshot_params.except(:image))
      invalid_error.record.errors[:image].each { |msg| screenshot.errors.add(:image, msg) }
      screenshot
    end
  end

  # Route a form-supplied image replacement through the primary ScreenshotImage
  # so the new blob is what readers render. Resets dimension metadata + enqueues
  # re-analysis so Screenshot#status ends up :ready after the job finishes.
  def attach_replacement_image!(image_param)
    si = @screenshot.primary_image || @screenshot.screenshot_images.create!(viewport: :desktop)
    si.with_lock do
      si.image.attach(image_param)
      si.update!(status: :pending, width: nil, height: nil)
    end
    si.ensure_dimension_processing
  end
end
