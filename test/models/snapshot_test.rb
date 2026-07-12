# frozen_string_literal: true

require "test_helper"

class SnapshotTest < ActiveSupport::TestCase
  MANIFEST_DIGEST = "a" * 64

  test "git_commit column preserves the migration's 40-character limit" do
    assert_equal 40, Snapshot.columns_hash.fetch("git_commit").limit
  end

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

  test "git_commit must be 7-40 hexadecimal characters" do
    snapshot = Snapshot.new(project: projects(:alice_project), taken_at: Time.current)

    snapshot.git_commit = "a" * 6
    assert_not snapshot.valid?, "git_commit shorter than 7 chars should fail format"

    snapshot.git_commit = "a" * 41
    assert_not snapshot.valid?, "git_commit longer than 40 chars should fail format"

    snapshot.git_commit = ("z" * 7)
    assert_not snapshot.valid?, "Non-hex git_commit should fail format"

    snapshot.git_commit = "abc1234"
    assert snapshot.valid?, "7-char hex git_commit should be valid"

    snapshot.git_commit = "a" * 40
    assert snapshot.valid?, "40-char hex git_commit should be valid"
  end

  test "git_commit is normalized to lowercase on save" do
    snapshot = projects(:alice_project).snapshots.create!(
      git_commit: "ABC1234DEF",
      taken_at: Time.current
    )

    assert_equal "abc1234def", snapshot.git_commit
  end

  test "git_commit normalization strips surrounding whitespace" do
    # CLI paste regression — leading/trailing whitespace from a shell var
    # would otherwise fail the GIT_COMMIT_FORMAT regex silently.
    snapshot = projects(:alice_project).snapshots.create!(
      git_commit: "  abc1234\n",
      taken_at: Time.current
    )

    assert_equal "abc1234", snapshot.git_commit
  end

  test "git_commit normalization is safe on frozen strings" do
    frozen_commit = "AbC1234".freeze
    snapshot = projects(:alice_project).snapshots.create!(
      git_commit: frozen_commit,
      taken_at: Time.current
    )

    assert_equal "abc1234", snapshot.git_commit
  end

  test "defaults taken_at to current time" do
    travel_to Time.zone.parse("2026-05-14 13:15:00") do
      snapshot = Snapshot.create!(project: projects(:alice_project), git_commit: "abc1234")

      assert_equal Time.current, snapshot.taken_at
    end
  end

  test "rejects taken_at too far in the future" do
    snapshot = Snapshot.new(
      project: projects(:alice_project),
      git_commit: "abc1234",
      taken_at: Time.current + 10.minutes
    )

    assert_not snapshot.valid?, "Snapshot should reject future capture timestamps"
    assert_includes snapshot.errors[:taken_at], "can't be in the future"
  end

  test "allows duplicate git_commit snapshots for repeated captures" do
    project = projects(:alice_project)

    assert_difference -> { project.snapshots.count }, 2 do
      project.snapshots.create!(git_commit: "abc1234", taken_at: 2.hours.ago)
      project.snapshots.create!(git_commit: "abc1234", taken_at: 1.hour.ago)
    end
  end

  test "manifest digest is optional for legacy snapshots and normalized when present" do
    legacy = projects(:alice_project).snapshots.create!(git_commit: "abc1234")
    manifest = projects(:alice_project).snapshots.create!(
      git_commit: "def5678",
      manifest_digest: "  #{MANIFEST_DIGEST.upcase}\n"
    )

    assert_nil legacy.manifest_digest
    assert_equal MANIFEST_DIGEST, manifest.manifest_digest
  end

  test "manifest digest must be a SHA-256 hex digest" do
    snapshot = projects(:alice_project).snapshots.build(
      git_commit: "abc1234",
      manifest_digest: "not-a-digest"
    )

    assert_not snapshot.valid?
    assert_includes snapshot.errors[:manifest_digest], "must be a 64-character hexadecimal SHA-256"
  end

  test "manifest digest is unique per project at validation and database levels" do
    project = projects(:alice_project)
    project.snapshots.create!(git_commit: "abc1234", manifest_digest: MANIFEST_DIGEST)

    duplicate = project.snapshots.build(git_commit: "def5678", manifest_digest: MANIFEST_DIGEST)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:manifest_digest], "has already been taken"

    assert_raises(ActiveRecord::RecordNotUnique) do
      duplicate.save!(validate: false)
    end
  end

  test "same manifest digest is allowed in different projects" do
    projects(:alice_project).snapshots.create!(git_commit: "abc1234", manifest_digest: MANIFEST_DIGEST)
    snapshot = projects(:bob_project).snapshots.build(git_commit: "abc1234", manifest_digest: MANIFEST_DIGEST)

    assert snapshot.valid?
  end

  test "aggregate state follows expected image attachment and processing state" do
    project = projects(:alice_project)
    snapshot = project.snapshots.create!(git_commit: "abc1234", manifest_digest: MANIFEST_DIGEST)
    screenshot = project.pages.first.screenshots.create!(
      title: "Manifest capture",
      snapshot: snapshot,
      manifest_entry_digest: "b" * 64
    )
    desktop = screenshot.screenshot_images.create!(
      viewport: :desktop, content_sha256: "c" * 64, expected_content_type: "image/png"
    )
    mobile = screenshot.screenshot_images.create!(
      viewport: :mobile, content_sha256: "d" * 64, expected_content_type: "image/png"
    )

    assert_equal "awaiting_upload", snapshot.aggregate_state

    [ desktop, mobile ].each do |image|
      image.image.attach(
        io: StringIO.new(File.binread(Rails.root.join("test/fixtures/files/test_image.png"))),
        filename: "#{image.viewport}.png",
        content_type: "image/png"
      )
    end
    assert_equal "processing", snapshot.aggregate_state

    mobile.update!(status: :failed)
    assert_equal "failed", snapshot.aggregate_state

    desktop.update!(status: :ready)
    mobile.update!(status: :ready)
    assert_equal "ready", snapshot.aggregate_state
  end

  test "recent scope returns full ordered array newest first" do
    assert_equal [ snapshots(:latest), snapshots(:earlier) ],
      projects(:alice_project).snapshots.recent.to_a
  end

  test "recent scope orders newest first across many distinct taken_at" do
    project = users(:alice).owned_projects.create!(name: "Ordering snapshots")
    oldest = project.snapshots.create!(git_commit: "1111111", taken_at: 3.days.ago)
    middle = project.snapshots.create!(git_commit: "2222222", taken_at: 2.days.ago)
    newest = project.snapshots.create!(git_commit: "3333333", taken_at: 1.day.ago)

    assert_equal [ newest, middle, oldest ], project.snapshots.recent.to_a,
      "Snapshots should descend by taken_at across 3+ distinct timestamps"
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

  test "label uses the UTC date consistently across request zones" do
    snapshot = Snapshot.new(
      project: projects(:alice_project),
      git_commit: "abc1234def567890",
      taken_at: Time.iso8601("2026-05-14T23:00:00-05:00")
    )

    Time.use_zone("Hawaii") do
      assert_equal "2026-05-15 · abc1234", snapshot.label
    end
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

  test "destroying a screenshot leaves its snapshot intact" do
    # `dependent: :nullify` runs snapshot -> screenshots. The reverse
    # direction must not exist — destroying one screenshot should not
    # cascade to delete the snapshot or its sibling screenshots.
    snapshot = snapshots(:latest)
    screenshot = screenshots(:alice_screenshot)
    screenshot.update!(snapshot: snapshot)

    assert_no_difference -> { Snapshot.count }, "Snapshot should survive its screenshot's destroy" do
      screenshot.destroy
    end

    assert Snapshot.exists?(snapshot.id), "Snapshot row should still exist after screenshot destroy"
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
