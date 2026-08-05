# frozen_string_literal: true

require "test_helper"

module Oauth
  class DynamicClientRegistrationConcurrencyTest < ActiveSupport::TestCase
    self.use_transactional_tests = false

    setup do
      @suffix = SecureRandom.hex(8)
      @baseline = Doorkeeper::Application.where(dynamic: true).count
    end

    teardown do
      Doorkeeper::Application.where("name LIKE ?", "Concurrent DCR #{@suffix}%").destroy_all
    end

    test "concurrent unique registrations cannot cross global capacity" do
      ready = Queue.new
      start = Queue.new
      results = Queue.new

      with_maximum_dynamic_clients(@baseline + 1) do
        threads = 2.times.map do |index|
          Thread.new do
            ActiveRecord::Base.connection_pool.with_connection do
              ready << true
              start.pop
              result = DynamicClientRegistration.call(
                client_name: "Concurrent DCR #{@suffix} #{index}",
                redirect_uris: [ "http://127.0.0.1:#{45_000 + index}/callback" ]
              )
              results << result.created
            rescue DynamicClientRegistration::CapacityExceeded
              results << :capacity_exceeded
            rescue StandardError => error
              results << error
            end
          ensure
            ActiveRecord::Base.connection_pool.release_connection
          end
        end

        2.times { ready.pop }
        2.times { start << true }
        threads.each(&:join)
      end

      outcomes = 2.times.map { results.pop }
      assert outcomes.none?(Exception), -> { outcomes.grep(Exception).map(&:full_message).join("\n") }
      assert_equal [ true, :capacity_exceeded ].sort_by(&:to_s), outcomes.sort_by(&:to_s)
      dynamic_client_count = Doorkeeper::Application.uncached do
        Doorkeeper::Application.where(dynamic: true).count
      end
      assert_equal @baseline + 1, dynamic_client_count
    end

    private

    def with_maximum_dynamic_clients(limit)
      singleton_class = DynamicClientRegistration.singleton_class
      original = DynamicClientRegistration.method(:maximum_dynamic_clients)
      singleton_class.define_method(:maximum_dynamic_clients) { limit }
      yield
    ensure
      singleton_class&.define_method(:maximum_dynamic_clients, original)
    end
  end
end
