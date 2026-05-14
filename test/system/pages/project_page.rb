# frozen_string_literal: true

module Pages
  module ProjectPage
    # --- Selectors ---

    PAGE_CARD = '[data-testid="page-card"]'
    PAGE_CARD_NAME = '[data-testid="page-card-name"]'
    SNAPSHOT_SIDEBAR = '[data-testid="snapshot-sidebar"]'
    SNAPSHOT_SIDEBAR_ITEM = '[data-testid="snapshot-sidebar-item"]'
    SNAPSHOT_SIDEBAR_CLEAR = '[data-testid="snapshot-sidebar-clear"]'
    DEFAULT_WAIT_SECONDS = 10

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
      assert_selector SNAPSHOT_SIDEBAR, wait: DEFAULT_WAIT_SECONDS
    end

    def assert_snapshot_listed(label)
      assert_selector SNAPSHOT_SIDEBAR_ITEM, text: label, wait: DEFAULT_WAIT_SECONDS
    end

    # Asserts the first `names.size` cards match `names` in order. Strict prefix
    # by design: the tail can be in any order (caller passes only the rows whose
    # order matters), but earlier silent regressions in the head are caught.
    def assert_page_cards_in_order(*names)
      assert_selector PAGE_CARD, minimum: names.size, wait: DEFAULT_WAIT_SECONDS
      actual = page_card_names.first(names.size)
      assert_equal names, actual,
        "Page cards should start with #{names.inspect}, got #{actual.inspect}"
    end

    def assert_only_page_cards(*names)
      assert_selector PAGE_CARD, count: names.size, wait: DEFAULT_WAIT_SECONDS
      actual = page_card_names
      assert_equal names.sort, actual.sort,
        "Expected only #{names.inspect}, got #{actual.inspect}"
    end

    def assert_page_card_visible(name)
      assert_selector PAGE_CARD_NAME, text: name, wait: DEFAULT_WAIT_SECONDS
    end

    def assert_page_card_not_visible(name)
      assert_no_selector PAGE_CARD_NAME, text: name, wait: DEFAULT_WAIT_SECONDS
    end

    def assert_page_card_screenshot(name, screenshot_id)
      card = page_card(name)
      assert_equal screenshot_id.to_i, card["data-screenshot-id"].to_i,
        "Page card #{name.inspect} should reference screenshot #{screenshot_id}, got #{card['data-screenshot-id'].inspect}"
    end

    private

    def page_card_names
      all(PAGE_CARD, wait: DEFAULT_WAIT_SECONDS).map { |card| card.find(PAGE_CARD_NAME).text }
    end

    def page_card(name)
      find(PAGE_CARD, text: name, wait: DEFAULT_WAIT_SECONDS)
    end
  end
end
