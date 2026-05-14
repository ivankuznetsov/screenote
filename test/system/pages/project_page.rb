# frozen_string_literal: true

module Pages
  module ProjectPage
    # --- Selectors ---

    PAGE_CARD = '[data-testid="page-card"]'
    PAGE_CARD_NAME = '[data-testid="page-card-name"]'
    SNAPSHOT_SIDEBAR = '[data-testid="snapshot-sidebar"]'
    SNAPSHOT_SIDEBAR_ITEM = '[data-testid="snapshot-sidebar-item"]'
    SNAPSHOT_SIDEBAR_CLEAR = '[data-testid="snapshot-sidebar-clear"]'

    # --- Actions ---

    def click_snapshot(label)
      within SNAPSHOT_SIDEBAR do
        click_link label
      end
      wait_for_turbo
    end

    def clear_snapshot_filter
      find(SNAPSHOT_SIDEBAR_CLEAR).click
      wait_for_turbo
    end

    # --- Assertions ---

    def assert_snapshot_sidebar_visible
      assert_selector SNAPSHOT_SIDEBAR, wait: 10
    end

    def assert_snapshot_listed(label)
      assert_selector SNAPSHOT_SIDEBAR_ITEM, text: label, wait: 10
    end

    def assert_page_cards_in_order(*names)
      assert_selector PAGE_CARD, minimum: names.size, wait: 10
      assert_equal names, page_card_names.first(names.size)
    end

    def assert_only_page_cards(*names)
      assert_selector PAGE_CARD, count: names.size, wait: 10
      assert_equal names.sort, page_card_names.sort
    end

    def assert_page_card_visible(name)
      assert_selector PAGE_CARD_NAME, text: name, wait: 10
    end

    def assert_page_card_not_visible(name)
      assert_no_selector PAGE_CARD_NAME, text: name, wait: 5
    end

    def assert_page_card_screenshot(name, screenshot_id)
      card = page_card(name)
      assert_equal screenshot_id.to_i, card["data-screenshot-id"].to_i
    end

    private

    def page_card_names
      all(PAGE_CARD, wait: 10).map { |card| card.find(PAGE_CARD_NAME).text }
    end

    def page_card(name)
      find(PAGE_CARD, text: name, wait: 10)
    end
  end
end
