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
    @snapshots = @project.snapshots.recent.limit(10).to_a
    @active_snapshot = active_snapshot
    # Keep the sidebar at most 10 rows: if the active snapshot is older than
    # the recent-10 window, prepend it and drop the oldest tail row so the
    # "recent 10" contract is enforced rather than approximated.
    if @active_snapshot && @snapshots.none? { |s| s.id == @active_snapshot.id }
      @snapshots.unshift(@active_snapshot)
      @snapshots.pop
    end
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
    return if params[:snapshot_id].blank?

    # Reuse the already-loaded recent-10 list when the active id is in it so
    # the common case (user clicks the just-created top snapshot) skips one
    # extra SELECT.
    cached = @snapshots.detect { |s| s.id.to_s == params[:snapshot_id].to_s }
    cached || @project.snapshots.find_by(id: params[:snapshot_id])
  end

  def ordered_pages
    scope = @project.pages

    scope = if @active_snapshot
      # Match `page_thumbnails`'s `.ready` filter so a snapshot whose only
      # screenshot for a page is still pending doesn't render a thumbnail-less
      # card with no fallback.
      scope.joins(:screenshots)
        .merge(Screenshot.ready)
        .where(screenshots: { snapshot_id: @active_snapshot.id })
    else
      scope.left_joins(:screenshots)
    end

    scope = scope
      .select("pages.*, COUNT(screenshots.id) AS screenshots_count_cache")
      .group("pages.id")
      .order(Arel.sql("COALESCE(MAX(screenshots.created_at), pages.created_at) DESC"))

    if @active_snapshot
      scope
    else
      scope.includes(latest_screenshot: { screenshot_images: { image_attachment: :blob } })
    end
  end

  def page_thumbnails
    return {} unless @active_snapshot

    page_ids = @pages.map(&:id)
    return {} if page_ids.empty?

    # Order candidates by created_at (not MAX(id)) so a backfill/import that
    # inserts older rows with newer ids cannot silently flip which screenshot
    # renders as the thumbnail. Bucket the first per page in Ruby to keep the
    # query SQLite/Postgres-portable without window functions.
    candidates = @active_snapshot.screenshots
      .ready
      .where(page_id: page_ids)
      .order(created_at: :desc, id: :desc)
      .includes(screenshot_images: { image_attachment: :blob })

    candidates.each_with_object({}) do |screenshot, acc|
      acc[screenshot.page_id] ||= screenshot
    end
  end
end
