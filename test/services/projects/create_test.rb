# frozen_string_literal: true

require "test_helper"

module Projects
  class CreateTest < ActiveSupport::TestCase
    Deployment = Data.define(:billing?)

    test "creates an owned project and owner membership for a writable user principal" do
      user = users(:free_user)
      principal = AuthenticatedPrincipal.for_user(user)

      assert_difference [ "Project.count", "ProjectMembership.count" ], 1 do
        project = Projects::Create.call(
          principal: principal,
          attributes: { name: "Shared operation" },
          deployment: Deployment.new(false)
        )

        assert_equal user, project.creator
        assert project.owner?(user)
      end
    end

    test "rejects read-only oauth and project principals" do
      read_token = create_oauth_token(
        application: create_oauth_application,
        user: users(:alice),
        scopes: "mcp_read"
      )
      read_principal = AuthenticatedPrincipal.for_oauth_token(read_token)
      api_key = api_keys(:alice_key)
      issuer = users(:alice)
      api_key.define_singleton_method(:issued_by_user) { issuer }
      key_principal = AuthenticatedPrincipal.for_api_key(api_key)

      assert_no_difference [ "Project.count", "ProjectMembership.count" ] do
        assert_raises(Projects::Create::Forbidden) do
          Projects::Create.call(
            principal: read_principal,
            attributes: { name: "Read only" },
            deployment: Deployment.new(false)
          )
        end
        assert_raises(Projects::Create::Forbidden) do
          Projects::Create.call(
            principal: key_principal,
            attributes: { name: "API key escape" },
            deployment: Deployment.new(false)
          )
        end
      end
    end

    test "keeps the SaaS project quota" do
      user = users(:free_user)
      user.owned_projects.create!(name: "Existing")

      assert_no_difference [ "Project.count", "ProjectMembership.count" ] do
        assert_raises(Projects::Create::LimitReached) do
          Projects::Create.call(
            principal: AuthenticatedPrincipal.for_user(user),
            attributes: { name: "Over quota" },
            deployment: Deployment.new(true)
          )
        end
      end
    end

    test "self-hosted project creation is unlimited" do
      user = users(:free_user)
      user.owned_projects.create!(name: "Existing")

      assert_difference [ "Project.count", "ProjectMembership.count" ], 1 do
        Projects::Create.call(
          principal: AuthenticatedPrincipal.for_user(user),
          attributes: { name: "Unlimited core" },
          deployment: Deployment.new(false)
        )
      end
    end
  end
end
