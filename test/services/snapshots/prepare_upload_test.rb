# frozen_string_literal: true

require "test_helper"

module Snapshots
  class PrepareUploadTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    class FailingQueueAdapter < ActiveJob::QueueAdapters::TestAdapter
      def enqueue(_job)
        raise "queue unavailable"
      end
    end

    test "creates a complete multi-page multi-viewport graph atomically" do
      payload = snapshot_manifest_payload

      assert_difference "Snapshot.count", 1 do
        assert_difference "Screenshot.count", 2 do
          assert_difference "ScreenshotImage.count", 3 do
            assert_difference "Page.count", 2 do
              result = PrepareUpload.call(project: projects(:alice_project), payload: payload)
              assert result.created
              assert_equal "awaiting_upload", result.snapshot.aggregate_state
            end
          end
        end
      end
    end

    test "identical replay returns the same graph without mutation" do
      payload = snapshot_manifest_payload
      first = PrepareUpload.call(project: projects(:alice_project), payload: payload)

      assert_no_enqueued_jobs(only: ScreenshotDimensionJob) do
        assert_no_difference [ "Snapshot.count", "Screenshot.count", "ScreenshotImage.count", "Page.count" ] do
          replay = PrepareUpload.call(project: projects(:alice_project), payload: payload)

          assert_not replay.created
          assert_equal first.snapshot.id, replay.snapshot.id
          assert_equal first.snapshot.screenshots.order(:id).ids, replay.snapshot.screenshots.order(:id).ids
        end
      end
    end

    test "identical replay re-enqueues attached pending images after a lost enqueue" do
      bytes = file_fixture("test_image.png").binread
      entry = snapshot_entry(page: "Recover upload", viewport: :desktop, seed: "recover-upload")
      entry[:content_sha256] = Digest::SHA256.hexdigest(bytes)
      payload = snapshot_manifest_payload(entries: [ entry ])
      first = PrepareUpload.call(project: projects(:alice_project), payload: payload)
      image = first.snapshot.screenshot_images.sole

      original_adapter = ScreenshotDimensionJob.queue_adapter
      ScreenshotDimensionJob.queue_adapter = FailingQueueAdapter.new

      begin
        assert_raises(RuntimeError, match: /queue unavailable/) do
          AttachImage.call(
            image: image,
            io: StringIO.new(bytes),
            declared_content_type: "image/png",
            declared_length: bytes.bytesize
          )
        end
      ensure
        ScreenshotDimensionJob.queue_adapter = original_adapter
      end

      assert image.reload.image.attached?
      assert image.status_pending?
      clear_enqueued_jobs

      assert_enqueued_with(job: ScreenshotDimensionJob, args: [ image, image.image.blob.id ]) do
        replay = PrepareUpload.call(project: projects(:alice_project), payload: payload)

        assert_not replay.created
        assert_equal first.snapshot.id, replay.snapshot.id
      end
    end

    test "identical replay does not re-enqueue an attached ready image" do
      payload = snapshot_manifest_payload(entries: [ snapshot_entry(page: "Ready upload", viewport: :desktop, seed: "ready-upload") ])
      first = PrepareUpload.call(project: projects(:alice_project), payload: payload)
      image = first.snapshot.screenshot_images.sole
      image.image.attach(
        io: file_fixture("test_image.png").open,
        filename: "test_image.png",
        content_type: "image/png"
      )
      image.update!(status: :ready, width: 10, height: 10)
      clear_enqueued_jobs

      assert_no_enqueued_jobs(only: ScreenshotDimensionJob) do
        replay = PrepareUpload.call(project: projects(:alice_project), payload: payload)

        assert_not replay.created
      end
    end

    test "concurrent identical preparations converge on one graph" do
      entries = [
        snapshot_entry(page: "Concurrent Public CLI", viewport: :desktop, seed: "concurrent-desktop"),
        snapshot_entry(page: "Concurrent Public CLI", viewport: :mobile, seed: "concurrent-mobile")
      ]
      payload = snapshot_manifest_payload(entries: entries)
      ready = Queue.new
      start = Queue.new
      results = Queue.new
      errors = Queue.new

      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            ready << true
            start.pop
            results << PrepareUpload.call(project: projects(:alice_project), payload: payload)
          rescue StandardError => e
            errors << e
          end
        end
      end
      2.times { ready.pop }
      2.times { start << true }
      threads.each(&:join)

      assert errors.empty?, errors.size.times.map { errors.pop.full_message }.join("\n")
      prepared = 2.times.map { results.pop }
      assert_equal 1, prepared.count(&:created)
      assert_equal 1, prepared.map { |result| result.snapshot.id }.uniq.length
      assert_equal 1, projects(:alice_project).snapshots.where(manifest_digest: payload[:manifest_digest]).count
    ensure
      snapshot = projects(:alice_project).snapshots.find_by(manifest_digest: payload&.dig(:manifest_digest))
      snapshot&.screenshots&.destroy_all
      snapshot&.destroy
      projects(:alice_project).pages.where(name: "Concurrent Public CLI").destroy_all
    end

    test "rejects multiple screenshot groups for one page in a new snapshot" do
      payload = snapshot_manifest_payload(entries: [
        snapshot_entry(page: "Hive Web", title: "Task board", viewport: :desktop, seed: "task-board"),
        snapshot_entry(page: "hive web", title: "Agent status", viewport: :desktop, seed: "agent-status")
      ])

      assert_no_difference [ "Snapshot.count", "Screenshot.count", "ScreenshotImage.count", "Page.count" ] do
        error = assert_raises(PrepareUpload::InvalidContract) do
          PrepareUpload.call(project: projects(:alice_project), payload: payload)
        end

        assert_equal "each page must identify exactly one screenshot per snapshot", error.message
      end
    end

    test "uses lowercase rather than Unicode case folding for page identity" do
      payload = snapshot_manifest_payload(entries: [
        snapshot_entry(page: "Straße", title: "German street", viewport: :desktop, seed: "german-street"),
        snapshot_entry(page: "STRASSE", title: "Capital street", viewport: :desktop, seed: "capital-street")
      ])

      assert_difference({ "Snapshot.count" => 1, "Screenshot.count" => 2, "Page.count" => 2 }) do
        result = PrepareUpload.call(project: projects(:alice_project), payload: payload)

        assert result.created
      end
    end

    test "rejects page groups that the database resolves to the same Page" do
      payload = snapshot_manifest_payload(entries: [
        snapshot_entry(page: "Straße", title: "German street", viewport: :desktop, seed: "db-german-street"),
        snapshot_entry(page: "STRASSE", title: "Capital street", viewport: :desktop, seed: "db-capital-street")
      ])
      resolved_page = projects(:alice_project).pages.create!(name: "Database identity")
      service = PrepareUpload.new(project: projects(:alice_project), payload: payload)
      service.define_singleton_method(:find_or_create_page!) { |_name| resolved_page }

      assert_no_difference [ "Snapshot.count", "Screenshot.count", "ScreenshotImage.count", "Page.count" ] do
        error = assert_raises(PrepareUpload::InvalidContract) do
          service.call
        end

        assert_equal "invalid_manifest", error.code
        assert_equal "each page must identify exactly one screenshot per snapshot", error.message
      end
    end

    test "resumes an existing legacy manifest with multiple screenshot groups for one page" do
      payload = snapshot_manifest_payload(entries: [
        snapshot_entry(page: "Legacy Hive Web", title: "Task board", viewport: :desktop, seed: "legacy-task-board"),
        snapshot_entry(page: "legacy hive web", title: "Agent status", viewport: :desktop, seed: "legacy-agent-status")
      ])
      contract = PrepareUpload.new(project: projects(:alice_project), payload: payload).send(:normalize_contract)
      snapshot = create_legacy_snapshot_graph(contract)

      assert_no_difference [ "Snapshot.count", "Screenshot.count", "ScreenshotImage.count", "Page.count" ] do
        replay = PrepareUpload.call(project: projects(:alice_project), payload: payload)

        assert_not replay.created
        assert_equal snapshot.id, replay.snapshot.id
      end
    end

    test "invalid contracts create no rows" do
      invalid_payloads = [
        snapshot_manifest_payload.merge(version: 2),
        snapshot_manifest_payload.merge(git_commit: "bad"),
        snapshot_manifest_payload.merge(taken_at: "2026-07-10"),
        snapshot_manifest_payload.merge(manifest_digest: "0" * 64),
        snapshot_manifest_payload(entries: []),
        snapshot_manifest_payload(entries: [ snapshot_entry(page: "Bad", viewport: :watch, seed: "bad") ]),
        snapshot_manifest_payload(entries: [ snapshot_entry(page: "Bad", viewport: :desktop, seed: "bad", mime_type: "image/gif") ]),
        snapshot_manifest_payload(entries: [
          snapshot_entry(page: "Duplicate", viewport: :desktop, seed: "one"),
          snapshot_entry(page: "Duplicate", viewport: :desktop, seed: "two")
        ])
      ]

      invalid_payloads.each do |payload|
        assert_no_difference [ "Snapshot.count", "Screenshot.count", "ScreenshotImage.count", "Page.count" ] do
          assert_raises(PrepareUpload::InvalidContract) do
            PrepareUpload.call(project: projects(:alice_project), payload: payload)
          end
        end
      end
    end

    test "changed content establishes a distinct capture" do
      original = snapshot_manifest_payload
      changed_entries = default_snapshot_entries.deep_dup
      changed_entries.first[:content_sha256] = Digest::SHA256.hexdigest("changed bytes")
      changed = snapshot_manifest_payload(entries: changed_entries)

      first = PrepareUpload.call(project: projects(:alice_project), payload: original)
      second = PrepareUpload.call(project: projects(:alice_project), payload: changed)

      assert_not_equal first.snapshot.id, second.snapshot.id
      assert_not_equal first.snapshot.manifest_digest, second.snapshot.manifest_digest
    end

    test "replay rejects a stored graph that no longer matches its contract" do
      payload = snapshot_manifest_payload
      first = PrepareUpload.call(project: projects(:alice_project), payload: payload)
      first.snapshot.screenshot_images.first.update_column(:content_sha256, "f" * 64)

      error = assert_raises(PrepareUpload::Conflict) do
        PrepareUpload.call(project: projects(:alice_project), payload: payload)
      end
      assert_equal "manifest_conflict", error.code
    end

    test "replay uses the same lowercase Page identity as new manifests" do
      payload = snapshot_manifest_payload(entries: [
        snapshot_entry(page: "Straße", title: "German street", viewport: :desktop, seed: "replay-german-street"),
        snapshot_entry(page: "STRASSE", title: "Capital street", viewport: :desktop, seed: "replay-capital-street")
      ])
      contract = PrepareUpload.new(project: projects(:alice_project), payload: payload).send(:normalize_contract)
      snapshot = create_legacy_snapshot_graph(contract)
      german_group, capital_group = contract.groups
      capital_page = snapshot.screenshots.find_by!(manifest_entry_digest: capital_group.digest).page
      snapshot.screenshots.find_by!(manifest_entry_digest: german_group.digest).update_columns(page_id: capital_page.id)

      error = assert_raises(PrepareUpload::Conflict) do
        PrepareUpload.call(project: projects(:alice_project), payload: payload)
      end

      assert_equal "manifest_conflict", error.code
      assert_equal "stored screenshot metadata does not match the manifest", error.message
    end

    private

    def create_legacy_snapshot_graph(contract)
      project = projects(:alice_project)
      snapshot = project.snapshots.create!(
        git_commit: contract.git_commit,
        taken_at: contract.taken_at,
        manifest_digest: contract.manifest_digest
      )
      contract.groups.each do |group|
        screenshot = snapshot.screenshots.build(
          page: Page.find_or_create_by_name!(project, group.page),
          title: group.title,
          manifest_entry_digest: group.digest
        )
        screenshot.save!(validate: false)
        group.entries.each do |entry|
          screenshot.screenshot_images.create!(
            viewport: entry.viewport,
            content_sha256: entry.content_sha256,
            expected_content_type: entry.mime_type
          )
        end
      end
      snapshot
    end
  end
end
