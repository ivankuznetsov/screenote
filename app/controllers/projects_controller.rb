# frozen_string_literal: true

class ProjectsController < ApplicationController
  include ProjectAuthorization

  before_action :set_project, only: %i[show edit update destroy]
  before_action :require_owner!, only: %i[edit update destroy]
  before_action :require_project_quota!, only: %i[new create]

  def index
    @memberships_by_project = Current.user.project_memberships.includes(:project).index_by(&:project_id)
    @projects = Current.user.projects.order(updated_at: :desc)
                  .includes(pages: { latest_screenshot: { image_attachment: :blob } })
  end

  def show
    @is_owner = @project.owner?(Current.user)
    @snapshots = @project.snapshots.recent.limit(10)
    @active_snapshot = active_snapshot
    @pages = ordered_pages.to_a
    @page_thumbnails = page_thumbnails
  end

  def new
    @project = Current.user.owned_projects.build
  end

  def create
    Current.user.with_lock do
      unless Current.user.can_create_project?
        redirect_to subscription_path,
          alert: "You've reached the free plan limit of 1 project. Upgrade to Pro for unlimited projects."
        return
      end

      @project = Current.user.owned_projects.build(project_params)

      if @project.save
        redirect_to @project, notice: "Project created."
      else
        render :new, status: :unprocessable_entity
      end
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Project updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    redirect_to projects_path, notice: "Project deleted."
  end

  private

  def require_project_quota!
    return if Current.user.can_create_project?

    redirect_to subscription_path,
      alert: "You've reached the free plan limit of 1 project. Upgrade to Pro for unlimited projects."
  end

  def project_params
    params.require(:project).permit(:name, :description)
  end

  def active_snapshot
    return unless params[:snapshot_id].present?

    @project.snapshots.find_by(id: params[:snapshot_id])
  end

  def ordered_pages
    scope = @project.pages

    scope = if @active_snapshot
      scope.joins(:screenshots).where(screenshots: { snapshot_id: @active_snapshot.id })
    else
      scope.left_joins(:screenshots)
    end

    scope
      .select("pages.*, COUNT(screenshots.id) AS screenshots_count_cache, MAX(screenshots.created_at) AS latest_screenshot_at")
      .group("pages.id")
      .order(Arel.sql("COALESCE(MAX(screenshots.created_at), pages.created_at) DESC"))
      .includes(latest_screenshot: { screenshot_images: { image_attachment: :blob } })
  end

  def page_thumbnails
    return {} unless @active_snapshot

    @active_snapshot.screenshots
      .where(page_id: @pages.map(&:id))
      .includes(screenshot_images: { image_attachment: :blob })
      .order(created_at: :desc, id: :desc)
      .each_with_object({}) do |screenshot, thumbnails|
        thumbnails[screenshot.page_id] ||= screenshot
      end
  end
end
