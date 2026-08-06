# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"
require "json"
require "open3"
require "tmpdir"

class SelfHostedReadinessTest < ActionDispatch::IntegrationTest
  PRODUCTION_ROLE_PROBE = <<~'RUBY'.freeze
    root = ENV.fetch("SCREENOTE_TEST_STORAGE_ROOT")
    configs = ActiveRecord::Base.configurations.configurations.map do |config|
      next config unless config.env_name == "production"

      hash = config.configuration_hash.except(:url).merge(
        database: File.join(root, "#{config.name}.sqlite3")
      )
      ActiveRecord::DatabaseConfigurations::HashConfig.new(config.env_name, config.name, hash)
    end
    ActiveRecord::Base.connection_handler.clear_all_connections!(:all)
    ActiveRecord::Base.configurations = configs
    {
      primary: ActiveRecord::Base,
      cache: SolidCache::Record,
      queue: SolidQueue::Record,
      cable: SolidCable::Record
    }.each { |role, model| model.establish_connection(role) }
    ActiveRecord::Tasks::DatabaseTasks.prepare_all

    readiness = Screenote::Readiness.new(storage_root: root)
    before = readiness.ready?
    SolidCable::Record.connection_pool.with_connection do |connection|
      connection.drop_table(:solid_cable_messages)
      connection.schema_cache.clear!
    end
    puts({ before: before, after_missing_schema: readiness.ready? }.to_json)
  RUBY
  HTTPS_PROBE = <<~'RUBY'.freeze
    Screenote::Readiness.singleton_class.define_method(:ready?) { true }
    request = Rack::MockRequest.new(Rails.application)
    ready = request.get("/ready", "HTTP_HOST" => "127.0.0.1")
    up = request.get("/up", "HTTP_HOST" => "127.0.0.1")
    puts({
      ready_status: ready.status,
      ready_body: JSON.parse(ready.body),
      ready_location: ready["location"],
      up_status: up.status,
      up_location: up["location"]
    }.to_json)
  RUBY

  test "readiness returns only generic ready and not-ready responses" do
    with_readiness_result(true) do
      get "/ready"

      assert_response :ok
      assert_equal({ "status" => "ready" }, JSON.parse(response.body))
      assert_equal "no-store", response.headers["Cache-Control"]
    end

    with_readiness_result(false) do
      get "/ready"

      assert_response :service_unavailable
      assert_equal({ "status" => "not_ready" }, JSON.parse(response.body))
      assert_equal "no-store", response.headers["Cache-Control"]
    end
  end

  test "readiness hides unexpected exception details" do
    with_readiness_result(-> { raise "private-provider-detail" }) do
      get "/ready"

      assert_response :service_unavailable
      assert_equal({ "status" => "not_ready" }, JSON.parse(response.body))
      assert_not_includes response.body, "private-provider-detail"
    end
  end

  test "up remains the Rails process liveness endpoint" do
    route = Rails.application.routes.recognize_path("/up", method: :get)

    assert_equal "rails/health", route.fetch(:controller)
    assert_equal "show", route.fetch(:action)
    get "/up"
    assert_response :success
  end

  test "readiness verifies every database role, the writable volume, and selected storage configuration" do
    Dir.mktmpdir("screenote-readiness") do |directory|
      role_connections = readiness_role_connections
      storage_service = ProviderMethodTrap.new
      storage_services = { self_hosted_local: storage_service }
      deployment = Struct.new(:active_storage_service).new(:self_hosted_local)
      readiness = Screenote::Readiness.new(
        role_connections: role_connections,
        storage_root: directory,
        storage_services: storage_services,
        deployment: deployment
      )

      assert readiness.ready?
      assert_equal(
        Screenote::Readiness::ROLE_TABLES,
        role_connections.transform_values { |connection| connection.connection_pool.connection.checked_table }
      )
      assert_empty Dir.children(directory)

      role_connections.fetch(:queue).connection_pool.connection.table_present = false
      assert_not readiness.ready?
    end
  end

  test "readiness fails generically when the selected storage service is absent" do
    Dir.mktmpdir("screenote-readiness") do |directory|
      deployment = Struct.new(:active_storage_service).new(:self_hosted_s3)
      readiness = Screenote::Readiness.new(
        role_connections: readiness_role_connections,
        storage_root: directory,
        storage_services: {},
        deployment: deployment
      )

      assert_not readiness.ready?
    end
  end

  test "production readiness uses all four prepared role databases" do
    Dir.mktmpdir("screenote-production-readiness") do |directory|
      stdout, stderr, status = Open3.capture3(
        production_environment.merge("SCREENOTE_TEST_STORAGE_ROOT" => directory),
        "bin/rails", "runner", PRODUCTION_ROLE_PROBE,
        chdir: Rails.root.to_s
      )

      assert status.success?, stderr
      payload = JSON.parse(stdout.lines.reverse.find { |line| line.lstrip.start_with?("{") })
      assert payload.fetch("before")
      assert_not payload.fetch("after_missing_schema")
    end
  end

  test "production local probes bypass canonical host and HTTPS redirects" do
    stdout, stderr, status = Open3.capture3(
      production_environment.merge("SCREENOTE_BASE_URL" => "https://screenote.internal"),
      "bin/rails", "runner", HTTPS_PROBE,
      chdir: Rails.root.to_s
    )

    assert status.success?, stderr
    payload = JSON.parse(stdout.lines.reverse.find { |line| line.lstrip.start_with?("{") })
    assert_equal 200, payload.fetch("ready_status")
    assert_equal({ "status" => "ready" }, payload.fetch("ready_body"))
    assert_nil payload.fetch("ready_location")
    assert_equal 200, payload.fetch("up_status")
    assert_nil payload.fetch("up_location")
  end

  private

  FakeConnection = Struct.new(:table_present, :checked_table) do
    def data_source_exists?(table)
      self.checked_table = table
      table_present
    end
  end

  FakePool = Struct.new(:connection) do
    def with_connection
      yield connection
    end
  end

  FakeRoleConnection = Struct.new(:connection_pool)

  class ProviderMethodTrap
    def method_missing(name, *)
      raise "readiness called provider method #{name}"
    end

    def respond_to_missing?(*, **)
      true
    end
  end

  def readiness_role_connections
    Screenote::Readiness::ROLE_TABLES.to_h do |role, _table|
      connection = FakeConnection.new(true)
      [ role, FakeRoleConnection.new(FakePool.new(connection)) ]
    end
  end

  def with_readiness_result(result)
    singleton_class = Screenote::Readiness.singleton_class
    original = Screenote::Readiness.method(:ready?)
    singleton_class.define_method(:ready?) do
      result.respond_to?(:call) ? result.call : result
    end
    yield
  ensure
    singleton_class.define_method(:ready?, original)
  end

  def production_environment
    {
      "RAILS_ENV" => "production",
      "RAILS_LOG_TO_STDOUT" => nil,
      "SCREENOTE_EDITION" => "self_hosted",
      "SCREENOTE_BASE_URL" => "http://screenote.internal:3005",
      "SECRET_KEY_BASE" => "a" * 64,
      "SCREENOTE_BOOTSTRAP_TOKEN" => "b" * 43
    }
  end
end
