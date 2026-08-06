# frozen_string_literal: true

return unless ENV["COVERAGE"] == "true"
return if defined?(SimpleCov) && SimpleCov.running

# `RUBYOPT` reaches subprocesses started by the test suite. Only the first Ruby
# process in each matrix command owns coverage; child runners must not append
# partial resultsets or write reports into output their parent is parsing.
coverage_root_pid = ENV["SCREENOTE_COVERAGE_ROOT_PID"]
return if coverage_root_pid && coverage_root_pid != Process.pid.to_s

ENV["SCREENOTE_COVERAGE_ROOT_PID"] = Process.pid.to_s

ENV["BUNDLE_GEMFILE"] ||= File.expand_path("../../Gemfile", __dir__)
require "bundler/setup"
require "simplecov"

SimpleCov.command_name "rails-test-#{ENV.fetch('TEST_ENV_NUMBER', '0')}"
SimpleCov.enable_coverage :branch
unless ENV["SCREENOTE_DEFER_COVERAGE_GATE"] == "1"
  SimpleCov.minimum_coverage 100
  SimpleCov.minimum_coverage line: 100, branch: 100
end
SimpleCov.start "rails" do
  add_filter "/test/"
  add_filter "/config/"
  add_filter "/db/"
  add_filter "/vendor/"
end
