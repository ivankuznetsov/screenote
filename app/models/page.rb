# frozen_string_literal: true

class Page < ApplicationRecord
  belongs_to :project
  has_many :screenshots, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
  validates :name, uniqueness: { scope: :project_id, case_sensitive: false }

  scope :ordered, -> { order(:created_at) }
end
