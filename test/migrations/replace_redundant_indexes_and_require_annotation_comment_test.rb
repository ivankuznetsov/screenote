# frozen_string_literal: true

require "test_helper"
require Rails.root.join("db/migrate/20261111120000_replace_redundant_indexes_and_require_annotation_comment").to_s

class ReplaceRedundantIndexesAndRequireAnnotationCommentTest < ActiveSupport::TestCase
  include MigrationDatabaseConfigHelper

  self.fixture_table_names = []
  self.use_transactional_tests = false

  Migration = ReplaceRedundantIndexesAndRequireAnnotationComment
  TABLES = %i[
    annotation_comments annotations screenshot_images screenshots pages snapshots
    project_memberships image_attachment_batches projects users
  ].freeze

  class MigrationDatabaseRecord < ActiveRecord::Base
    self.abstract_class = true
  end

  setup do
    @database_class = MigrationDatabaseRecord
    @database_class.establish_connection(migration_database_config)
    @connection = @database_class.connection
    drop_schema
    create_legacy_schema
  end

  def after_teardown
    drop_schema if @connection
    super
  ensure
    @database_class&.remove_connection
  end

  test "replaces prefix indexes and requires comments without cascading away replies" do
    insert_annotation(comment: "Fix the header")

    run_migration(:up)

    Migration::PREFIX_INDEXES.each do |table, column|
      assert_not @connection.index_exists?(table, column, name: "index_#{table}_on_#{column}"), "#{table}.#{column}"
    end
    assert_not @connection.index_name_exists?(:screenshots, Migration::LEGACY_SCREENSHOTS_INDEX)
    assert @connection.index_exists?(:screenshots, %i[page_id created_at])
    assert_not @connection.columns(:annotations).find { |column| column.name == "comment" }.null
    assert_equal 1, row_count(:annotation_comments), "rebuilding annotations must not cascade into its replies"
    assert_equal :cascade, @connection.foreign_keys(:annotation_comments).sole.on_delete
  end

  test "refuses to invent text for an annotation without a comment" do
    id = insert_annotation(comment: nil)

    error = assert_raises(ActiveRecord::MigrationError) { run_migration(:up) }

    assert_includes error.message, "annotation IDs: #{id}"
    assert @connection.index_exists?(:annotations, :screenshot_id, name: "index_annotations_on_screenshot_id")
    assert_equal 1, row_count(:annotation_comments)
  end

  test "rolls back to the previous indexes and nullable comment" do
    insert_annotation(comment: "Fix the header")
    run_migration(:up)

    run_migration(:down)

    Migration::PREFIX_INDEXES.each do |table, column|
      assert @connection.index_exists?(table, column, name: "index_#{table}_on_#{column}"), "#{table}.#{column}"
    end
    assert @connection.index_exists?(:screenshots, :created_at, name: Migration::LEGACY_SCREENSHOTS_INDEX)
    assert_not @connection.index_exists?(:screenshots, %i[page_id created_at])
    assert @connection.columns(:annotations).find { |column| column.name == "comment" }.null
    assert_equal 1, row_count(:annotation_comments)
  end

  private

  def create_legacy_schema
    @connection.create_table(:users) { |table| table.string :email }
    @connection.create_table(:projects) { |table| table.references :user, foreign_key: true }
    @connection.create_table(:project_memberships) do |table|
      table.references :project, foreign_key: true
      table.references :user, foreign_key: true
    end
    @connection.add_index :project_memberships, %i[project_id user_id], unique: true
    @connection.create_table(:image_attachment_batches) do |table|
      table.references :user, foreign_key: true
      table.integer :state, default: 0, null: false
    end
    @connection.add_index :image_attachment_batches, %i[user_id state]
    @connection.create_table(:snapshots) do |table|
      table.references :project, foreign_key: true
      table.datetime :taken_at
    end
    @connection.add_index :snapshots, %i[project_id taken_at]
    @connection.create_table(:pages) do |table|
      table.references :project, foreign_key: true
      table.string :name
    end
    @connection.add_index :pages, "project_id, LOWER(name)", unique: true, name: "index_pages_on_project_id_and_lower_name"
    @connection.create_table(:screenshots) do |table|
      table.references :page, foreign_key: true
      table.datetime :created_at, null: false
    end
    @connection.add_index :screenshots, :created_at, name: Migration::LEGACY_SCREENSHOTS_INDEX
    @connection.create_table(:screenshot_images) do |table|
      table.references :screenshot, foreign_key: true
      table.integer :viewport, null: false
    end
    @connection.add_index :screenshot_images, %i[screenshot_id viewport], unique: true
    @connection.create_table(:annotations) do |table|
      table.references :screenshot, foreign_key: true
      table.integer :status, default: 0, null: false
      table.text :comment
    end
    @connection.add_index :annotations, %i[screenshot_id status]
    @connection.create_table(:annotation_comments) do |table|
      table.references :annotation, foreign_key: { on_delete: :cascade }
      table.text :body, null: false
      table.datetime :created_at, null: false
    end
    @connection.add_index :annotation_comments, %i[annotation_id created_at]
  end

  def insert_annotation(comment:)
    insert(:users, id: 1, email: "owner@example.test")
    insert(:projects, id: 1, user_id: 1)
    insert(:pages, id: 1, project_id: 1, name: "Home")
    insert(:screenshots, id: 1, page_id: 1, created_at: Time.current)
    insert(:annotations, id: 1, screenshot_id: 1, comment:)
    insert(:annotation_comments, id: 1, annotation_id: 1, body: "Reply", created_at: Time.current)
    1
  end

  def insert(table, **attributes)
    columns = attributes.keys.map { |column| @connection.quote_column_name(column) }.join(", ")
    quoted_values = attributes.values.map { |value| @connection.quote(value) }.join(", ")
    @connection.execute(<<~SQL.squish)
      INSERT INTO #{@connection.quote_table_name(table)} (#{columns}) VALUES (#{quoted_values})
    SQL
  end

  def row_count(table)
    @connection.select_value("SELECT COUNT(*) FROM #{@connection.quote_table_name(table)}").to_i
  end

  def run_migration(direction)
    capture_io do
      @connection.transaction do
        Migration.new.exec_migration(@connection, direction)
      end
    end
  end

  def drop_schema
    TABLES.each { |table| @connection.drop_table(table, if_exists: true, force: :cascade) }
  end
end
