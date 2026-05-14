# frozen_string_literal: true

require "test_helper"

class SnapshotTest < ActiveSupport::TestCase
  test "valid snapshot with project, git commit, and taken_at" do
    snapshot = Snapshot.new(
      project: projects(:alice_project),
      git_commit: "abc1234def567890abc1234def567890abc1234d",
      taken_at: Time.current
    )

    assert snapshot.valid?, "Snapshot should be valid with required attributes"
  end

  test "requires project" do
    snapshot = Snapshot.new(git_commit: "abc1234", taken_at: Time.current)

    assert_not snapshot.valid?, "Snapshot should be invalid without project"
  end

  test "requires git_commit" do
    snapshot = Snapshot.new(project: projects(:alice_project), taken_at: Time.current)

    assert_not snapshot.valid?, "Snapshot should be invalid without git_commit"
    assert snapshot.errors[:git_commit].any?, "Should have git_commit error"
  end

  test "git_commit max length 64" do
    snapshot = Snapshot.new(
      project: projects(:alice_project),
      git_commit: "a" * 65,
      taken_at: Time.current
    )

    assert_not snapshot.valid?, "Snapshot should be invalid with git_commit > 64 chars"

    snapshot.git_commit = "a" * 64
    assert snapshot.valid?, "Snapshot should be valid with git_commit = 64 chars"
  end

  test "requires taken_at" do
    snapshot = Snapshot.new(project: projects(:alice_project), git_commit: "abc1234")

    assert_not snapshot.valid?, "Snapshot should be invalid without taken_at"
    assert snapshot.errors[:taken_at].any?, "Should have taken_at error"
  end

  test "recent scope returns full ordered array newest first" do
    assert_equal [ snapshots(:latest), snapshots(:earlier) ],
      projects(:alice_project).snapshots.recent.to_a
  end

  test "recent scope tie-breaks by id when taken_at is identical" do
    same_time = Time.zone.parse("2026-05-14 12:00:00")
    older = projects(:alice_project).snapshots.create!(git_commit: "aaa1234", taken_at: same_time)
    newer = projects(:alice_project).snapshots.create!(git_commit: "bbb1234", taken_at: same_time)

    recent = projects(:alice_project).snapshots.recent.to_a
    older_idx = recent.index(older)
    newer_idx = recent.index(newer)
    assert newer_idx < older_idx,
      "Newer id should come first when taken_at ties (newer=#{newer_idx}, older=#{older_idx})"
  end

  test "short_commit truncates to seven characters" do
    assert_equal "abc1234", snapshots(:latest).short_commit
  end

  test "label returns date and short commit" do
    snapshot = Snapshot.new(
      project: projects(:alice_project),
      git_commit: "abc1234def567890",
      taken_at: Time.zone.parse("2026-05-14 12:00:00")
    )

    assert_equal "2026-05-14 · abc1234", snapshot.label
  end

  test "destroying snapshot nullifies screenshots via Rails dependent: :nullify" do
    snapshot = snapshots(:latest)
    screenshot = screenshots(:alice_screenshot)
    screenshot.update!(snapshot: snapshot)

    assert_no_difference "Screenshot.count" do
      snapshot.destroy
    end

    assert_nil screenshot.reload.snapshot_id
  end

  test "DB foreign key nullifies screenshot.snapshot_id when the row is deleted directly" do
    # Guards the DB-level ON DELETE NULLIFY: if a future migration drops the
    # FK action, raw SQL deletes would leave dangling snapshot_ids on
    # screenshots even though Rails callbacks pass — this test fails loudly
    # in that scenario.
    snapshot = snapshots(:latest)
    screenshot = screenshots(:alice_screenshot)
    screenshot.update!(snapshot: snapshot)

    ActiveRecord::Base.connection.execute(
      ActiveRecord::Base.sanitize_sql_for_conditions([ "DELETE FROM snapshots WHERE id = ?", snapshot.id ])
    )

    assert_nil screenshot.reload.snapshot_id, "DB FK should null out screenshot.snapshot_id"
  end
end
