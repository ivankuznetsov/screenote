class AddPageToScreenshots < ActiveRecord::Migration[8.1]
  class Page < ApplicationRecord; end
  class Screenshot < ApplicationRecord; end

  def up
    add_reference :screenshots, :page, null: true, foreign_key: true

    # Backfill: create one page per existing screenshot (1:1 migration)
    # Handle duplicate names within a project by appending counter
    seen = Hash.new(0)

    Screenshot.order(:created_at).find_each do |screenshot|
      key = [ screenshot.project_id, screenshot.title.to_s.downcase.strip ]
      seen[key] += 1
      name = seen[key] > 1 ? "#{screenshot.title} (#{seen[key]})" : screenshot.title

      page = Page.create!(
        project_id: screenshot.project_id,
        name: name,
        created_at: screenshot.created_at,
        updated_at: screenshot.updated_at
      )
      screenshot.update_column(:page_id, page.id)
    end

    change_column_null :screenshots, :page_id, false
    remove_reference :screenshots, :project, foreign_key: true
  end

  def down
    add_reference :screenshots, :project, null: true, foreign_key: true

    Screenshot.find_each do |screenshot|
      page = Page.find(screenshot.page_id)
      screenshot.update_column(:project_id, page.project_id)
    end

    change_column_null :screenshots, :project_id, false
    remove_reference :screenshots, :page, foreign_key: true
  end
end
