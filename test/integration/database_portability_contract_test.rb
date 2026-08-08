# frozen_string_literal: true

require "test_helper"

class DatabasePortabilityContractTest < ActiveSupport::TestCase
  PORTABLE_PATHS = [
    Rails.root.join("app"),
    Rails.root.join("db/migrate"),
    Rails.root.join("config/database.yml"),
    Rails.root.join(".github/workflows/ci.yml"),
    Rails.root.join(".github/workflows/release-qualification.yml"),
    Rails.root.join("script/release_test_matrix")
  ].freeze
  POSTGRESQL_SPECIFIC = /postgres(?:ql)?|pg_advisory|\bPG::/i

  test "application and release contracts do not depend on PostgreSQL-specific behavior" do
    violations = source_files.flat_map do |path|
      path.readlines.filter_map.with_index(1) do |line, line_number|
        "#{path.relative_path_from(Rails.root)}:#{line_number}" if line.match?(POSTGRESQL_SPECIFIC)
      end
    end

    assert_empty violations,
      "PostgreSQL-specific application behavior found:\n#{violations.join("\n")}"
  end

  private

  def source_files
    PORTABLE_PATHS.flat_map do |path|
      path.directory? ? path.glob("**/*").select(&:file?) : path
    end
  end
end
