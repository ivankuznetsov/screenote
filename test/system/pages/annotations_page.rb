# frozen_string_literal: true

module Pages
  module AnnotationsPage
    # --- Selectors ---

    ANNOTATION_FORM = "#annotation-form"
    IN_PLACE_ANNOTATION_FORM = "#annotation-form.annotation-form--in-place"
    COMMENT_FIELD = 'textarea[name="annotation[comment]"]'
    SAVE_BUTTON = '#annotation-form input[type="submit"]'
    CANCEL_BUTTON = '[data-testid="cancel-button"]'

    ANNOTATION_ITEM = '[data-testid="annotation-item"]'
    ANNOTATION_COMMENT = '[data-testid="annotation-comment"]'

    ANNOTATION_PIN = ".annotation-pin"
    POINT_ANNOTATION_PIN = ".annotation-pin--point"
    REGION_ANNOTATION_PIN = ".annotation-pin--region"
    DRAFT_POINT_ANNOTATION_PIN = ".annotation-pin--draft.annotation-pin--point"
    DRAFT_REGION_ANNOTATION_PIN = ".annotation-pin--draft.annotation-pin--region"

    REPLY_TOGGLE = '[data-testid="reply-toggle"]'
    REPLY_TEXTAREA = '[data-testid="reply-textarea"]'
    REPLY_BUTTON = '[data-testid="reply-button"]'
    THREAD_ENTRY = '[data-testid="thread-entry"]'
    THREAD_AUTHOR_MARKER = '[data-testid="thread-author-marker"]'

    UNRESOLVE_BUTTON = '[data-testid="unresolve-button"]'
    SUBMIT_UNRESOLVE_BUTTON = '[data-testid="submit-unresolve-button"]'
    UNRESOLVE_TEXTAREA = ".annotation-thread__textarea"

    THREAD_BADGE_RESOLVED = ".annotation-thread__badge--resolved"
    THREAD_BADGE_REOPENED = ".annotation-thread__badge--reopened"
    THREAD_BODY = ".annotation-thread__body"

    # --- Actions ---

    def fill_annotation_comment(text)
      find(COMMENT_FIELD).set(text)
    end

    def submit_annotation
      find(SAVE_BUTTON).click
    end

    def cancel_annotation
      find(CANCEL_BUTTON).click
    end

    def reply_to_annotation(comment_text, reply:)
      within find(ANNOTATION_ITEM, text: comment_text) do
        find(REPLY_TOGGLE).click
        find(REPLY_TEXTAREA).set(reply)
        find(REPLY_BUTTON).click
      end
    end

    def resolve_annotation(comment_text)
      within find(ANNOTATION_ITEM, text: comment_text) do
        click_button "Resolve"
      end
    end

    def unresolve_annotation(comment_text, reason:)
      within find(ANNOTATION_ITEM, text: comment_text) do
        find(UNRESOLVE_BUTTON).click
        find(UNRESOLVE_TEXTAREA).set(reason)
        find(SUBMIT_UNRESOLVE_BUTTON).click
      end
    end

    # --- Assertions ---

    def assert_annotation_form_visible
      assert_selector ANNOTATION_FORM, wait: 10
    end

    def assert_in_place_annotation_form_visible
      assert_selector IN_PLACE_ANNOTATION_FORM, wait: 10
      assert_selector ".screenshot-canvas__image-wrapper > #{IN_PLACE_ANNOTATION_FORM}", wait: 10
      assert_no_selector ".annotation-sidebar #{ANNOTATION_FORM}"
    end

    def assert_annotation_form_hidden
      assert_no_selector ANNOTATION_FORM, wait: 5
    end

    def assert_annotation_visible(comment_text)
      assert_selector ANNOTATION_COMMENT, text: comment_text, wait: 10
    end

    def assert_annotation_not_visible(comment_text)
      assert_no_selector ANNOTATION_COMMENT, text: comment_text, wait: 5
    end

    def assert_annotation_count(count)
      assert_selector ANNOTATION_ITEM, count: count, wait: 10
    end

    def assert_annotation_resolved(comment_text)
      assert_selector "#{ANNOTATION_ITEM}[data-status=\"resolved\"]", text: comment_text, wait: 10
    end

    def assert_annotation_open(comment_text)
      assert_selector "#{ANNOTATION_ITEM}[data-status=\"open\"]", text: comment_text, wait: 10
    end

    def assert_annotation_sidebar_empty
      assert_no_selector ANNOTATION_ITEM, wait: 5
    end

    def assert_thread_has_resolved_badge(comment_text)
      within find(ANNOTATION_ITEM, text: comment_text) do
        assert_selector THREAD_BADGE_RESOLVED, wait: 10
      end
    end

    def assert_thread_has_reopened_badge(comment_text)
      within find(ANNOTATION_ITEM, text: comment_text) do
        assert_selector THREAD_BADGE_REOPENED, wait: 10
      end
    end

    def assert_thread_body(comment_text, thread_text)
      within find(ANNOTATION_ITEM, text: comment_text) do
        assert_selector THREAD_BODY, text: thread_text, wait: 10
      end
    end

    def assert_thread_reply(comment_text, reply:, author:)
      within find(ANNOTATION_ITEM, text: comment_text) do
        assert_selector THREAD_ENTRY, text: reply, wait: 10
        assert_selector THREAD_ENTRY, text: author, wait: 10
      end
    end
  end
end
