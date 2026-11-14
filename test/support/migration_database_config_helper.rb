# frozen_string_literal: true

module MigrationDatabaseConfigHelper
  def migration_database_config
    ENV["MIGRATION_TEST_DATABASE_URL"].presence || { adapter: "sqlite3", database: ":memory:" }
  end
end
