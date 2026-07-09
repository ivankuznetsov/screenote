# frozen_string_literal: true

module Pages
  module PagesPage
    # --- Selectors ---

    PAGE_CARD = '[data-testid="page-card"]'
    PAGE_CARD_NAME = '[data-testid="page-card-name"]'
    PAGE_CARD_THUMBNAIL = ".page-card__thumbnail"
    PAGE_CARD_THUMBNAIL_IMG = ".page-card__thumbnail img"
    PAGE_CARD_PLACEHOLDER = ".page-card__placeholder"
    PAGE_FORM = '[data-testid="page-form"]'
    PAGE_FORM_ERRORS = '[data-testid="page-form-errors"]'
    PAGE_DETAIL_TITLE = '[data-testid="page-detail-title"]'
    DELETE_PAGE_BUTTON = '[data-testid="delete-page-button"]'

    # --- Actions ---

    def click_page(name)
      find(PAGE_CARD_NAME, text: name).click
    end

    def click_new_page
      click_link "New page"
      assert_selector PAGE_FORM, wait: 10
    end

    def fill_page_form(name:)
      fill_in "page[name]", with: name
    end

    def submit_page_form
      find('input[type="submit"]').click
    end

    def navigate_to_first_page
      first(PAGE_CARD).click
      assert_on_page_show
    end

    # --- Assertions ---

    def assert_on_page_show(name = nil)
      if name
        assert_selector PAGE_DETAIL_TITLE, text: name, wait: 10
      else
        assert_selector PAGE_DETAIL_TITLE, wait: 10
      end
    end

    def assert_page_card_visible(name)
      assert_selector PAGE_CARD_NAME, text: name, wait: 10
    end

    def assert_page_card_not_visible(name)
      assert_no_selector PAGE_CARD_NAME, text: name, wait: 5
    end

    def assert_page_form_error
      assert_selector PAGE_FORM_ERRORS, wait: 5
    end

    def assert_page_version_count(name, count)
      card = find(PAGE_CARD, text: name)
      assert card.has_text?("#{count} version"), "Expected page '#{name}' to show #{count} version(s)"
    end

    def assert_page_card_has_thumbnail(name)
      card = find(PAGE_CARD, text: name)
      assert card.has_no_css?(PAGE_CARD_PLACEHOLDER), "Page '#{name}' should not show placeholder when image exists"
    end

    def assert_page_card_has_placeholder(name)
      card = find(PAGE_CARD, text: name)
      assert card.has_css?(PAGE_CARD_PLACEHOLDER), "Page '#{name}' should display placeholder when no screenshots"
      assert card.has_no_css?(PAGE_CARD_THUMBNAIL_IMG), "Page '#{name}' should not display thumbnail image when no screenshots"
    end
  end
end
