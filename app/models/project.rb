# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :creator, class_name: "User", foreign_key: :user_id, inverse_of: :owned_projects
  has_many :project_memberships, dependent: :destroy
  has_many :members, through: :project_memberships, source: :user
  has_many :project_invitations, dependent: :destroy
  has_many :pages, dependent: :destroy
  has_many :screenshots, through: :pages
  has_many :snapshots, dependent: :destroy
  has_many :api_keys, dependent: :destroy
  has_many :oauth_access_grants,
    class_name: "Doorkeeper::AccessGrant",
    foreign_key: :project_id,
    inverse_of: false,
    dependent: :delete_all
  has_many :oauth_access_tokens,
    class_name: "Doorkeeper::AccessToken",
    foreign_key: :project_id,
    inverse_of: false,
    dependent: :delete_all

  validates :name, presence: true, length: { maximum: 255 }

  before_destroy :flag_destroy_in_progress, prepend: true
  after_create :create_owner_membership

  attr_accessor :_destroy_in_progress

  def member?(check_user)
    project_memberships.exists?(user_id: check_user.id)
  end

  def role_for(check_user)
    project_memberships.find_by(user_id: check_user.id)&.role&.to_sym
  end

  def owner?(check_user)
    project_memberships.exists?(user_id: check_user.id, role: :owner)
  end

  def thumbnail_screenshots(limit = 4)
    pages.lazy.filter_map { |p| p.latest_screenshot if p.latest_screenshot&.primary_image&.image&.attached? }.first(limit)
  end

  def pages_ordered_by_latest(snapshot: nil)
    scope = pages
    pages_table = Page.arel_table
    screenshots_table = Screenshot.arel_table

    if snapshot
      scope = scope.joins(:screenshots)
        .merge(Screenshot.ready)
        .where(screenshots: { snapshot_id: snapshot.id })
      screenshot_ids = screenshots_table[:id]
      screenshot_times = screenshots_table[:created_at]
    else
      scope = scope.left_joins(:screenshots)
      ready = screenshots_table[:status].eq(Screenshot.statuses[:ready])
      screenshot_ids = screenshots_table[:id]
      screenshot_times = Arel::Nodes::Case.new.when(ready).then(screenshots_table[:created_at])
    end

    screenshots_count = Arel::Nodes::NamedFunction.new("COUNT", [ screenshot_ids ])
      .as("screenshots_count_cache")
    latest_screenshot_at = Arel::Nodes::NamedFunction.new("MAX", [ screenshot_times ])
    sort_timestamp = Arel::Nodes::NamedFunction.new(
      "COALESCE", [ latest_screenshot_at, pages_table[:created_at] ]
    )

    scope = scope
      .select(pages_table[Arel.star], screenshots_count)
      .group(pages_table[:id])
      .order(sort_timestamp.desc)

    return scope if snapshot

    scope.includes(
      latest_screenshot: {
        screenshot_images: ScreenshotImage::OVERVIEW_IMAGE_PRELOAD
      }
    )
  end

  private

  def create_owner_membership
    project_memberships.create!(user: creator, role: :owner)
  end

  def flag_destroy_in_progress
    self._destroy_in_progress = true
  end
end
