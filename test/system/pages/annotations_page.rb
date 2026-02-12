# frozen_string_literal: true

module Pages
  module AnnotationsPage
    # --- Selectors ---

    ANNOTATION_FORM = "#annotation-form"
    COMMENT_FIELD = 'textarea[name="annotation[comment]"]'
    SAVE_BUTTON = '#annotation-form input[type="submit"]'
    CANCEL_BUTTON = "#annotation-form .btn--secondary"

    ANNOTATION_ITEM = ".annotation-item"
    ANNOTATION_COMMENT = ".annotation-item__comment"
    ANNOTATION_STATUS = ".annotation-item__status"
    ANNOTATION_NUMBER = ".annotation-item__number"
    RESOLVE_BUTTON = ".annotation-item__actions .btn--secondary"
    DELETE_ANNOTATION_BUTTON = ".annotation-item__actions .btn--danger"

    ANNOTATION_PIN = ".annotation-pin"

    # --- Actions ---

    def fill_annotation_comment(text)
      find(COMMENT_FIELD).fill_in with: text
    end

    def submit_annotation
      find(SAVE_BUTTON).click
    end

    def cancel_annotation
      find(CANCEL_BUTTON).click
    end

    # --- Assertions ---

    def assert_annotation_form_visible
      assert_selector ANNOTATION_FORM, wait: 10
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
      item = find(ANNOTATION_ITEM, text: comment_text)
      assert item.matches_css?(".annotation-item--resolved"), "Annotation '#{comment_text}' should be resolved"
    end
  end
end
