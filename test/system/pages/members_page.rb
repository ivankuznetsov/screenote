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
    ROLE_BADGE_OWNER = ".role-badge--owner"
    PENDING_LABEL = ".project-members__pending-label"
    SECTION_TITLE = ".project-members__section-title"
    AUTOCOMPLETE_ITEM = ".autocomplete-suggestions__item"

    # --- Actions ---

    def invite_email(email)
      fill_in "project_invitation[email]", with: email
      find(INVITE_BUTTON).click
    end

    def type_in_invite_field(text)
      field = find(INVITE_INPUT)
      field.fill_in with: ""
      field.send_keys(text)
    end

    # --- Assertions ---

    def assert_on_members_page
      assert_selector MEMBERS_TITLE, text: "Members", wait: 10
    end

    def assert_member_listed(email)
      assert_selector MEMBER_EMAIL, text: email, wait: 10
    end

    def assert_invite_form_visible
      assert_selector INVITE_FORM, wait: 10
    end

    def assert_pending_invitation(email)
      within(".project-members__section", text: "Pending invitations") do
        assert_selector MEMBER_EMAIL, text: email
      end
    end

    def assert_autocomplete_visible
      assert_selector AUTOCOMPLETE_ITEM, wait: 10
    end

    def assert_autocomplete_hidden
      assert_no_selector AUTOCOMPLETE_ITEM, wait: 5
    end

    def assert_autocomplete_suggests(email)
      assert_selector AUTOCOMPLETE_ITEM, text: email, wait: 10
    end

    def assert_owner_badge_for(email)
      item = find(MEMBER_ITEM, text: email)
      within(item) { assert_selector ROLE_BADGE_OWNER }
    end
  end
end
