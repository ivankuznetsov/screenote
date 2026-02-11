ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    fixtures :all
  end
end

module SignInHelper
  def sign_in(user)
    post session_path, params: { email: user.email, password: "password123" }
  end
end

class ActionDispatch::IntegrationTest
  include SignInHelper
end
