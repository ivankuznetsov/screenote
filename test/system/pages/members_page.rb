# frozen_string_literal: true

module Pages
  module MembersPage
    # --- Selectors ---

    MEMBERS_TITLE = ".page-header__title"
    INVITE_FORM = ".project-members__invite-form"
    INVITE_INPUT = ".project-members__invite-input"
    INVITE_BUTTON = 'input[type="submit"][value="Invite"]'
    MEMBER_ITEM = ".project-members__item"
    MEMBER_EMAIL = ".project-members__email"
    ROLE_BADGE = ".role-badge"
    ROLE_BADGE_OWNER = ".role-badge--owner"
    ROLE_BADGE_MEMBER = ".role-badge--member"
    PENDING_LABEL = ".project-members__pending-label"
    SECTION_TITLE = ".project-members__section-title"

    # --- Actions ---

    def visit_members(project_path)
      visit "#{project_path}/memberships"
      assert_selector MEMBERS_TITLE, text: "Members", wait: 10
    end

    def invite_email(email)
      fill_in "project_invitation[email]", with: email
      find(INVITE_BUTTON).click
    end

    # --- Assertions ---

    def assert_on_members_page
      assert_selector MEMBERS_TITLE, text: "Members", wait: 10
    end

    def assert_member_listed(email)
      assert_selector MEMBER_EMAIL, text: email, wait: 10
    end

    def assert_member_not_listed(email)
      assert_no_selector MEMBER_EMAIL, text: email, wait: 5
    end

    def assert_invite_form_visible
      assert_selector INVITE_FORM, wait: 10
    end

    def assert_no_invite_form
      assert_no_selector INVITE_FORM, wait: 5
    end

    def assert_pending_invitation(email)
      within(".project-members__section", text: "Pending invitations") do
        assert_selector MEMBER_EMAIL, text: email
      end
    end

    def assert_no_pending_invitation(email)
      assert_no_selector "#{PENDING_LABEL}", text: email, wait: 5
    end

    def assert_owner_badge_for(email)
      item = find(MEMBER_ITEM, text: email)
      within(item) { assert_selector ROLE_BADGE_OWNER }
    end

    def assert_member_badge_for(email)
      item = find(MEMBER_ITEM, text: email)
      within(item) { assert_selector ROLE_BADGE_MEMBER }
    end
  end
end
