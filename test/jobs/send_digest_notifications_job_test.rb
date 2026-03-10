# frozen_string_literal: true

require "test_helper"

class SendDigestNotificationsJobTest < ActiveSupport::TestCase
  include ActionMailer::TestHelper

  setup do
    @annotation = annotations(:point_annotation)
    @author = @annotation.user # alice
    @resolver = users(:bob)
  end

  test "sends digest email for unnotified resolved annotations" do
    resolution = create_resolution(@annotation, resolver: @resolver)

    assert_emails 1 do
      SendDigestNotificationsJob.perform_now
    end

    resolution.reload
    assert resolution.notified_at.present?, "Resolution comment should be marked as notified"
  end

  test "groups multiple resolutions into a single email per author" do
    region = annotations(:region_annotation)
    create_resolution(@annotation, resolver: @resolver)
    create_resolution(region, resolver: @resolver)

    assert_emails 1 do
      SendDigestNotificationsJob.perform_now
    end
  end

  test "sends separate emails to different authors" do
    bob_annotation = annotations(:bob_annotation)
    create_resolution(@annotation, resolver: @resolver)
    create_resolution(bob_annotation, resolver: @author) # alice resolves bob's annotation

    assert_emails 2 do
      SendDigestNotificationsJob.perform_now
    end
  end

  test "skips self-resolutions but still marks them as notified" do
    resolution = create_resolution(@annotation, resolver: @author) # alice resolves her own

    assert_no_emails do
      SendDigestNotificationsJob.perform_now
    end

    resolution.reload
    assert resolution.notified_at.present?, "Self-resolution should still be marked as notified"
  end

  test "skips blank email authors but still marks comments as notified" do
    @author.update_column(:email, "")
    resolution = create_resolution(@annotation, resolver: @resolver)

    assert_no_emails do
      SendDigestNotificationsJob.perform_now
    end

    resolution.reload
    assert resolution.notified_at.present?, "Comment for blank-email author should still be marked as notified"
  end

  test "does not re-send already notified resolutions" do
    resolution = create_resolution(@annotation, resolver: @resolver)
    resolution.update_column(:notified_at, 1.hour.ago)

    assert_no_emails do
      SendDigestNotificationsJob.perform_now
    end
  end

  test "marks comments as notified per-author so delivery failure does not cause duplicates" do
    bob_annotation = annotations(:bob_annotation)
    alice_resolution = create_resolution(@annotation, resolver: @resolver)
    bob_resolution = create_resolution(bob_annotation, resolver: @author)

    # First run: sends both emails
    assert_emails 2 do
      SendDigestNotificationsJob.perform_now
    end

    # Both should be marked notified
    assert alice_resolution.reload.notified_at.present?, "Alice's resolution should be marked notified"
    assert bob_resolution.reload.notified_at.present?, "Bob's resolution should be marked notified"

    # Second run: no duplicates
    assert_no_emails do
      SendDigestNotificationsJob.perform_now
    end
  end

  test "does not send for non-resolved comments" do
    @annotation.annotation_comments.create!(
      user: @resolver,
      body: "Just a regular comment",
      action: :comment
    )

    assert_no_emails do
      SendDigestNotificationsJob.perform_now
    end
  end

  private

  def create_resolution(annotation, resolver:)
    annotation.annotation_comments.create!(
      user: resolver,
      body: "Resolved this issue",
      action: :resolved
    )
  end
end
