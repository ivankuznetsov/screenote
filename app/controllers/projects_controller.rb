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
    recent_snapshots = @project.snapshots.recent.limit(10).to_a
    @active_snapshot = active_snapshot(recent_snapshots)
    @snapshots = snapshot_sidebar_items(recent_snapshots)
    @pages = @project.pages_ordered_by_latest(snapshot: @active_snapshot).to_a
    @page_thumbnails = @active_snapshot ? @active_snapshot.thumbnails_for(@pages) : {}
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

  def active_snapshot(recent_snapshots)
    return if params[:snapshot_id].blank?

    # Reuse the already-loaded recent-10 list when the active id is in it so
    # the common case (user clicks the just-created top snapshot) skips one
    # extra SELECT.
    cached = recent_snapshots.detect { |s| s.id.to_s == params[:snapshot_id].to_s }
    cached || @project.snapshots.find_by(id: params[:snapshot_id])
  end

  def snapshot_sidebar_items(recent_snapshots)
    return recent_snapshots unless @active_snapshot
    return recent_snapshots if recent_snapshots.any? { |s| s.id == @active_snapshot.id }

    [ @active_snapshot, *recent_snapshots ]
  end
end
