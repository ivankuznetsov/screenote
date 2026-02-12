# frozen_string_literal: true

class Screenshot < ApplicationRecord
  belongs_to :project
  has_many :annotations, dependent: :destroy
  has_one_attached :image

  enum :status, { pending: 0, ready: 1, failed: 2 }, default: :pending

  validates :title, presence: true
  validates :width, :height, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  after_create_commit :extract_dimensions_later

  private

  def extract_dimensions_later
    ScreenshotDimensionJob.perform_later(self)
  end
end
