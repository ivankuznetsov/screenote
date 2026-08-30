# frozen_string_literal: true

# screenote-edition: self_hosted

require "test_helper"

class AnnotationCommentTest < ActiveSupport::TestCase
  test "valid comment with user" do
    comment = AnnotationComment.new(
      annotation: annotations(:point_annotation),
      user: users(:alice),
      body: "This is a comment"
    )
    assert comment.valid?
  end

  test "valid comment with api_key" do
    comment = AnnotationComment.new(
      annotation: annotations(:point_annotation),
      api_key: api_keys(:alice_key),
      body: "AI resolved this"
    )
    assert comment.valid?
  end

  test "requires body" do
    comment = AnnotationComment.new(
      annotation: annotations(:point_annotation),
      user: users(:alice),
      body: ""
    )
    assert_not comment.valid?
    assert comment.errors[:body].any?
  end

  test "body cannot exceed 5000 characters" do
    comment = AnnotationComment.new(
      annotation: annotations(:point_annotation),
      user: users(:alice),
      body: "a" * 5001
    )
    assert_not comment.valid?
    assert comment.errors[:body].any?
  end

  test "requires an author (user or api_key)" do
    comment = AnnotationComment.new(
      annotation: annotations(:point_annotation),
      body: "No author"
    )
    assert_not comment.valid?
    assert comment.errors[:base].any?
  end

  test "default action is comment" do
    comment = AnnotationComment.new
    assert_equal "comment", comment.action
  end

  test "action enum values" do
    assert_equal 0, AnnotationComment.actions[:comment]
    assert_equal 1, AnnotationComment.actions[:resolved]
    assert_equal 2, AnnotationComment.actions[:reopened]
  end

  test "invalid with both user and api_key" do
    comment = AnnotationComment.new(
      annotation: annotations(:point_annotation),
      user: users(:alice),
      api_key: api_keys(:alice_key),
      body: "Both authors",
      action: :comment
    )
    assert_not comment.valid?, "Should not allow both user and api_key"
    assert_includes comment.errors[:base], "cannot have both user and api_key"
  end

  test "belongs to annotation" do
    comment = annotation_comments(:resolved_comment)
    assert_equal annotations(:resolved_annotation), comment.annotation
  end

  test "idempotency receipt fields are present together and use lowercase sha256" do
    comment = AnnotationComment.new(
      annotation: annotations(:point_annotation),
      user: users(:alice),
      body: "Durable image comment",
      idempotency_fingerprint: "a" * 64,
      request_digest: "b" * 64
    )

    assert_predicate comment, :valid?

    comment.request_digest = nil
    assert_not comment.valid?

    comment.request_digest = "B" * 64
    assert_not comment.valid?
  end

  test "idempotency receipt identity is immutable" do
    comment = annotations(:point_annotation).annotation_comments.create!(
      user: users(:alice),
      body: "Durable image comment",
      idempotency_fingerprint: "a" * 64,
      request_digest: "b" * 64
    )

    comment.idempotency_fingerprint = "c" * 64
    assert_not comment.valid?
    assert_includes comment.errors[:idempotency_fingerprint], "cannot change"
  end
end
