# frozen_string_literal: true

require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "author initials use an email identity and support Ivan Kuznetsov" do
    assert_equal "IK", annotation_author_initials(users(:admin))
    assert_equal "AL", annotation_author_initials(users(:alice))
    assert_equal "BO", annotation_author_initials(users(:bob))
  end

  test "author colors are stable and distinguish fixture collaborators" do
    alice_color = annotation_author_color(users(:alice))
    bob_color = annotation_author_color(users(:bob))

    assert_match(/\Aannotation-author-color--\d+\z/, alice_color)
    assert_equal alice_color, annotation_author_color(users(:alice))
    refute_equal alice_color, bob_color
  end

  test "API-authored replies receive a neutral AI identity" do
    assert_equal "AI", annotation_author_initials(api_keys(:alice_key))
    assert_equal "annotation-author-color--ai", annotation_author_color(api_keys(:alice_key))
  end
end
