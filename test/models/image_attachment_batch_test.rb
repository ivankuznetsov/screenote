# frozen_string_literal: true

require "test_helper"

class ImageAttachmentBatchTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @project = projects(:alice_project)
    @batch = ImageAttachmentBatch.open_for!(user: @user, project: @project)
  end

  test "a fresh batch is usable inside its activity window" do
    assert_predicate @batch, :usable?
    assert_not @batch.expired?
    assert_equal @batch.last_activity_at + ImageAttachmentBatch::EXPIRY, @batch.expires_at
  end

  test "an expired batch is no longer usable" do
    @batch.update_columns(last_activity_at: 25.hours.ago, expires_at: 1.minute.ago)

    assert_predicate @batch.reload, :expired?
    assert_not @batch.usable?
  end

  test "a claimed batch is no longer usable even inside its window" do
    @batch.update!(state: :claimed, claimed_annotation: annotations(:point_annotation))

    assert_not @batch.reload.usable?
    assert_not @batch.expired?
  end

  test "touch_activity! slides the whole expiry window forward" do
    @batch.update_columns(last_activity_at: 20.hours.ago, expires_at: 4.hours.from_now)
    now = Time.current

    @batch.touch_activity!(now)

    assert_in_delta now.to_f, @batch.reload.last_activity_at.to_f, 1
    assert_in_delta (now + ImageAttachmentBatch::EXPIRY).to_f, @batch.expires_at.to_f, 1
  end

  test "claimed_parent answers whichever message claimed the batch" do
    assert_nil @batch.claimed_parent

    @batch.update!(state: :claimed, claimed_annotation_comment: annotation_comments(:resolved_comment))

    assert_equal annotation_comments(:resolved_comment), @batch.reload.claimed_parent
  end

  test "database rejects an unknown state" do
    assert_raises ActiveRecord::StatementInvalid do
      insert_batch(state: 2, claimed: "NULL, NULL")
    end
  end

  test "database rejects an expiry that does not follow its activity stamp" do
    assert_raises ActiveRecord::StatementInvalid do
      insert_batch(expires_at: "2026-01-01 00:00:00", last_activity_at: "2026-01-02 00:00:00")
    end
  end

  test "database rejects an open batch that already names a claimed parent" do
    assert_raises ActiveRecord::StatementInvalid do
      insert_batch(state: 0, claimed: "#{annotations(:point_annotation).id}, NULL")
    end
  end

  test "database rejects a claimed batch that names both parents" do
    assert_raises ActiveRecord::StatementInvalid do
      insert_batch(
        state: 1,
        claimed: "#{annotations(:point_annotation).id}, #{annotation_comments(:resolved_comment).id}"
      )
    end
  end

  test "database rejects a claimed batch that names no parent" do
    assert_raises ActiveRecord::StatementInvalid do
      insert_batch(state: 1, claimed: "NULL, NULL")
    end
  end

  private

  def insert_batch(state: 0, claimed: "NULL, NULL",
    last_activity_at: "2026-01-01 00:00:00", expires_at: "2026-01-02 00:00:00")
    ImageAttachmentBatch.connection.execute(<<~SQL.squish)
      INSERT INTO image_attachment_batches
        (user_id, project_id, public_id, state, claimed_annotation_id, claimed_annotation_comment_id,
         last_activity_at, expires_at, created_at, updated_at)
      VALUES
        (#{@user.id}, #{@project.id}, '#{SecureRandom.urlsafe_base64(24)}', #{state}, #{claimed},
         '#{last_activity_at}', '#{expires_at}', '2026-01-01', '2026-01-01')
    SQL
  end
end
