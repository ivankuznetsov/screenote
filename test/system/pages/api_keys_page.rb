# frozen_string_literal: true

module Pages
  module ApiKeysPage
    # --- Selectors ---

    API_KEY_FORM = '[data-testid="api-key-form"]'
    API_KEY_TOKEN_REVEAL = '[data-testid="api-key-token-reveal"]'
    API_KEY_ITEM = '[data-testid="api-key-item"]'
    API_KEY_NAME = '[data-testid="api-key-name"]'
    API_KEY_LIST = '[data-testid="api-key-list"]'
    CREATE_API_KEY_BUTTON = '[data-testid="create-api-key-button"]'
    REVOKE_API_KEY_BUTTON = '[data-testid="revoke-api-key-button"]'

    # --- Actions ---

    def visit_api_keys(project_name)
      visit_projects
      click_project(project_name)
      assert_on_project_show(project_name)
      click_link "API keys"
      assert_selector '[data-testid="page-title"]', text: "API Keys", wait: 10
    end

    def create_api_key(project_name, key_name)
      visit_api_keys(project_name)
      find(CREATE_API_KEY_BUTTON).click
      assert_selector API_KEY_FORM, wait: 10

      fill_in "api_key[name]", with: key_name
      click_button "Create API key"

      assert_selector API_KEY_TOKEN_REVEAL, wait: 10
      find("#{API_KEY_TOKEN_REVEAL} code").text
    end

    def revoke_api_key(key_name)
      item = find(API_KEY_ITEM, text: key_name)
      accept_confirm do
        item.find(REVOKE_API_KEY_BUTTON).click
      end
      assert_selector API_KEY_ITEM, text: /Revoked/, wait: 10
    end

    # --- Assertions ---

    def assert_api_key_listed(name)
      assert_selector API_KEY_NAME, text: name, wait: 10
    end

    def assert_api_key_token_revealed
      assert_selector API_KEY_TOKEN_REVEAL, wait: 10
    end
  end
end
