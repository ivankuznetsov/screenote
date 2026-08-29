# frozen_string_literal: true

# Shared SQL budget instrumentation. Reads that preload media are only correct
# if their query count stays flat as records are added, so every such path
# measures the same way instead of reinventing a subscriber with its own
# tolerance.
module QueryBudgetHelper
  private

  def capture_app_queries
    Rails.cache.clear
    ActiveRecord::Base.connection.clear_query_cache
    queries = []
    callback = lambda do |*, payload|
      queries << payload[:sql] unless /SCHEMA|TRANSACTION/i.match?(payload[:name].to_s)
    end

    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  def assert_variant_records_preloaded(queries)
    variant_queries = queries.grep(/active_storage_variant_records/i)
    assert_equal 1, variant_queries.size,
      "Expected exactly one bulk variant-record preload, saw #{variant_queries.size}: #{variant_queries.inspect}"
  end
end
