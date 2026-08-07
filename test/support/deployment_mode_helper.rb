# frozen_string_literal: true

module DeploymentModeHelper
  VALID_MODES = %w[saas self_hosted].freeze

  def require_deployment_mode!(expected)
    expected = expected.to_s
    raise ArgumentError, "unknown Screenote deployment mode: #{expected.inspect}" unless VALID_MODES.include?(expected)

    configured = Screenote::Deployment.current.edition.to_s
    required = ENV["SCREENOTE_REQUIRED_MODE"].presence

    if required
      assert_includes VALID_MODES, required, "SCREENOTE_REQUIRED_MODE must name a supported edition"
      assert_equal expected, required,
        "this test belongs to the #{expected} suite, but the matrix required #{required}"
      assert_equal expected, configured,
        "SCREENOTE_EDITION booted as #{configured}; refusing to claim #{expected} coverage"
    elsif configured != expected
      skip "run with SCREENOTE_EDITION=#{expected}"
    end
  end

  def require_postgresql!
    adapter = ActiveRecord::Base.connection.adapter_name
    if ENV["SCREENOTE_REQUIRE_POSTGRESQL"] == "1"
      assert_equal "PostgreSQL", adapter,
        "the PostgreSQL matrix must not fall back to #{adapter}"
    elsif adapter != "PostgreSQL"
      skip "run with a PostgreSQL DATABASE_URL"
    end
  end

  def require_file_backed_sqlite!
    connection = ActiveRecord::Base.connection
    assert_equal "SQLite", connection.adapter_name

    database = connection.pool.db_config.database.to_s
    assert_not_equal ":memory:", database,
      "concurrency and persistence coverage requires file-backed SQLite"
    assert File.file?(database), "expected a file-backed SQLite database at #{database.inspect}"
  end
end
