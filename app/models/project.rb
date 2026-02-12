# frozen_string_literal: true

class Project < ApplicationRecord
  belongs_to :user
  has_many :screenshots, dependent: :destroy
  has_many :api_keys, dependent: :destroy

  validates :name, presence: true, length: { maximum: 255 }
end
