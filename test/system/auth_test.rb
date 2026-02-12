# frozen_string_literal: true

require_relative "application_system_test_case"
require_relative "pages/auth_page"

class AuthTest < ApplicationSystemTestCase
  include Pages::AuthPage

  test "sign in page renders correctly" do
    visit_sign_in

    assert_on_sign_in_page
    assert_selector SIGN_UP_LINK, text: "Create an account"
    assert_selector FORGOT_PASSWORD_LINK
    assert_selector MAGIC_LINK_BUTTON
  end

  test "sign in with valid credentials" do
    visit_sign_in
    fill_sign_in(email: "test@screenote.app", password: "password")
    submit_sign_in

    assert_signed_in(email: "test@screenote.app")
    assert_selector '[data-testid="page-title"], [data-testid="project-list"], [data-testid="empty-state"]', wait: 10
  end

  test "sign in with invalid credentials shows error" do
    visit_sign_in
    fill_sign_in(email: "test@screenote.app", password: "wrongpassword")
    submit_sign_in

    assert_auth_error
    assert_no_selector SIGN_OUT_BUTTON, wait: 2
  end

  test "sign in with non-existent email shows error" do
    visit_sign_in
    fill_sign_in(email: "nobody@example.com", password: "password")
    submit_sign_in

    assert_auth_error
  end

  test "sign out redirects to landing page" do
    login_as_test_user

    logout

    assert_selector ".landing-nav", wait: 10
    assert_no_selector SIGN_OUT_BUTTON, wait: 2
  end

  test "unauthenticated user is redirected to sign in" do
    visit "/projects"

    assert_on_sign_in_page
  end

  test "sign up page renders correctly" do
    visit_sign_up

    assert_selector SIGN_IN_TITLE, text: "Create your account"
    assert_selector SIGN_UP_EMAIL
    assert_selector SIGN_UP_PASSWORD
    assert_selector SIGN_UP_BUTTON
  end

  test "navigate from sign in to sign up" do
    visit_sign_in
    click_link "Create an account"

    assert_selector SIGN_IN_TITLE, text: "Create your account", wait: 10
  end

  test "navigate from sign in to forgot password" do
    visit_sign_in
    click_link "Forgot password?"

    assert_selector SIGN_IN_TITLE, text: "Reset Password", wait: 10
  end

  test "navigate from sign in to magic link" do
    visit_sign_in
    click_link "Sign in with Magic Link"

    assert_selector SIGN_IN_TITLE, text: "Magic Link", wait: 10
  end
end
