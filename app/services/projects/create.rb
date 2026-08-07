# frozen_string_literal: true

module Projects
  class Create
    class Forbidden < StandardError; end
    class LimitReached < StandardError; end

    def self.call(principal:, attributes:, deployment: Screenote::Deployment.current)
      new(principal: principal, attributes: attributes, deployment: deployment).call
    end

    def initialize(principal:, attributes:, deployment:)
      @principal = principal
      @attributes = attributes
      @deployment = deployment
    end

    def call
      raise Forbidden, "This principal cannot create projects" unless principal&.can_create_project?

      principal.user.with_lock do
        if deployment.billing? && !principal.user.can_create_project?(deployment: deployment)
          raise LimitReached, "Project limit reached for the current plan"
        end

        principal.user.owned_projects.create!(attributes)
      end
    end

    private

    attr_reader :principal, :attributes, :deployment
  end
end
