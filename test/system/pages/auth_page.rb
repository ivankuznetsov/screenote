# frozen_string_literal: true

module Pages
  module AuthPage
    # --- Selectors ---

    # Selectors below target rails_simple_auth gem markup (no data-testid available)
    SIGN_IN_FORM = ".rsa-auth-form"
    SIGN_IN_TITLE = ".rsa-auth-form__title"
    SIGN_UP_LINK = 'a[href="/sign_up"]'
    FORGOT_PASSWORD_LINK = 'a[href="/passwords/new"]'
    MAGIC_LINK_BUTTON = ".rsa-auth-form__magic-link-button"
    AUTH_ERROR = ".rsa-auth-form__error"
    SIGN_UP_EMAIL = 'input[name="user[email]"]'
    SIGN_UP_PASSWORD = 'input[name="user[password]"]'
    SIGN_UP_BUTTON = 'input[type="submit"][value="Sign Up"]'
    FLASH_NOTICE = '[data-testid="flash-notice"]'
    SIGN_OUT_BUTTON = '[data-testid="sign-out-button"]'
    USER_EMAIL = '[data-testid="user-email"]'

    # --- Actions ---

    def visit_sign_in
      visit "/session/new"
      assert_selector SIGN_IN_FORM, wait: 10
    end

    def visit_sign_up
      visit "/sign_up"
      assert_selector SIGN_IN_FORM, wait: 10
    end

    def fill_sign_in(email:, password:)
      fill_in "email", with: email
      fill_in "password", with: password
    end

    def submit_sign_in
      click_button "Sign In"
    end

    # --- Assertions ---

    def assert_signed_in(email: nil)
      assert_selector USER_EMAIL, text: email, wait: 10 if email
      assert_selector SIGN_OUT_BUTTON, wait: 10
    end

    def assert_on_sign_in_page
      assert_selector SIGN_IN_FORM, wait: 10
      assert_selector SIGN_IN_TITLE, text: "Sign In"
    end

    def assert_auth_error(text = nil)
      if text
        assert_selector AUTH_ERROR, text: text
      else
        assert_selector AUTH_ERROR
      end
    end

    def assert_flash_notice(text)
      assert_selector FLASH_NOTICE, text: text, wait: 10
    end
  end
end
