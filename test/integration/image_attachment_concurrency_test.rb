# frozen_string_literal: true

require "test_helper"
require_relative "../support/deterministic_concurrency_test_helper"

# SQLite proves the constraint contracts and the deterministic interleavings.
# The PostgreSQL qualification workflow runs this same file against real row
# locks so aggregate races, lock ordering, and atomic claim are exercised with
# production semantics.
class ImageAttachmentConcurrencyTest < ActiveSupport::TestCase
  include DeterministicConcurrencyTestHelper
  include ActiveJob::TestHelper

  self.use_transactional_tests = false

  setup do
    require_vips!
    @user = users(:alice)
    @project = projects(:alice_project)
    @screenshot = screenshots(:alice_screenshot)
    @highest_blob_id = ActiveStorage::Blob.maximum(:id).to_i
    @highest_annotation_id = Annotation.maximum(:id).to_i
    @highest_annotation_comment_id = AnnotationComment.maximum(:id).to_i
    @batch = build_batch
  end

  teardown do
    # These tests deliberately race real transactions across threads, and a
    # thread killed on timeout can leave its connection holding a write lock.
    # Dropping the pool keeps one hung race from failing every later test in
    # this worker.
    ApplicationRecord.connection_pool.disconnect!

    ImageAttachment.delete_all
    ImageAttachmentBatch.delete_all
    AnnotationComment.where("id > ?", @highest_annotation_comment_id).delete_all
    Annotation.where("id > ?", @highest_annotation_id).delete_all
    ActiveStorage::Blob.where("id > ?", @highest_blob_id).find_each(&:purge)
  end

  # The qualification workflow exists to run this file against real row locks.
  # Asserting the adapter is what stops that job from silently passing on the
  # SQLite behavior it was added to cover for.
  test "the qualification job runs against the server database it claims to" do
    unless ENV["SCREENOTE_SERVER_DATABASE_QUALIFICATION"] == "1"
      skip "server database qualification is opt-in"
    end

    assert_equal "PostgreSQL", ApplicationRecord.connection.adapter_name
  end

  test "concurrent submissions of one batch create exactly one message" do
    ingest_image(batch: @batch)

    outcomes = with_one_shot_instance_method_barrier(
      ImageAttachment, :update_columns, predicate: ->(record, *_args) { record.is_a?(ImageAttachment) }
    ) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { claim_result },
        second: -> { claim_result }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    parent_ids = outcomes.map { |result| result.parent.id }.uniq
    assert_equal 1, parent_ids.size
    assert_equal 1, outcomes.count(&:replayed?)
    assert_equal 1, Annotation.where(comment: "Look here").count
    assert_predicate @batch.reload, :state_claimed?
  end

  test "concurrent uploads cannot exceed the file limit" do
    (ImageAttachment::MAX_FILES - 1).times { |index| ingest_image(batch: @batch, client_key: "seed-#{index}") }
    bytes = image_bytes

    outcomes = with_one_shot_instance_method_barrier(
      ImageAttachment, :update!, predicate: ->(record, attributes) {
        record.is_a?(ImageAttachment) && attributes[:state] == :ready
      }
    ) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { safe_ingest(bytes, "race-a") },
        second: -> { safe_ingest(bytes, "race-b") }
      )
    end

    assert_equal ImageAttachment::MAX_FILES, ImageAttachment.where(image_attachment_batch: @batch).count
    assert_equal 1, outcomes.grep(ImageAttachments::Error).size
    assert_equal "too_many_files", outcomes.grep(ImageAttachments::Error).sole.code
  end

  # The 50 MB ceiling is the one every message is actually held to, so the race
  # is run against that constant rather than a stubbed one. The batch is seeded
  # up to exactly one more file's worth of room using recorded byte sizes, so
  # two concurrent commits both see room and only one can be allowed to take it.
  test "concurrent commits cannot exceed the fifty megabyte message total" do
    bytes = image_bytes
    headroom = ImageAttachment::MAX_TOTAL_BYTES - bytes.bytesize
    seed_sizes = [
      ImageAttachment::MAX_FILE_SIZE,
      ImageAttachment::MAX_FILE_SIZE,
      headroom - (2 * ImageAttachment::MAX_FILE_SIZE)
    ]
    seed_sizes.each_with_index do |size, index|
      @batch.image_attachments.create!(
        user: @user, project: @project, client_key: "seed-#{index}", state: :ready,
        media_type: "image/png", width: 1, height: 1, byte_size: size
      )
    end

    assert_equal headroom, @batch.reload.total_byte_size

    outcomes = with_one_shot_instance_method_barrier(
      ImageAttachment, :update!, predicate: ->(record, attributes) {
        record.is_a?(ImageAttachment) && attributes[:state] == :ready
      }
    ) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { safe_ingest(bytes, "total-a") },
        second: -> { safe_ingest(bytes, "total-b") }
      )
    end

    errors = outcomes.grep(ImageAttachments::Error)
    assert_equal 1, errors.size, -> { outcomes.map(&:inspect).inspect }
    assert_equal "batch_too_large", errors.sole.code
    assert_equal ImageAttachment::MAX_TOTAL_BYTES, @batch.reload.total_byte_size
  end

  test "removal loses to a concurrent claim rather than partially binding a message" do
    attachment = ingest_image(batch: @batch)

    outcomes = with_one_shot_instance_method_barrier(
      ImageAttachment, :update_columns, predicate: ->(record, *_args) { record.is_a?(ImageAttachment) }
    ) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { claim_result },
        second: -> { ImageAttachments::RemoveAttachment.call(batch: @batch.reload, attachment_id: attachment.id) }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    claimed = outcomes.grep(ImageAttachments::ClaimBatch::Result).sole
    assert_equal 1, claimed.parent.image_attachments.count
    assert_equal claimed.parent.id, attachment.reload.annotation_id
  end

  # Removal reserves the client key as a tombstone, so the row an upload tries
  # to create cannot be newer than the removal. The commit also rechecks that
  # marker under the batch lock before it can bind bytes.
  test "a removal during an upload stops that upload from binding its bytes" do
    bytes = image_bytes

    outcomes = with_one_shot_instance_method_barrier(
      ActiveStorage::Blob, :upload_without_unfurling, predicate: ->(record, *_args) {
        record.is_a?(ActiveStorage::Blob)
      }
    ) do |entered, release|
      run_settled_race(
        entered: entered,
        release: release,
        first: -> { safe_ingest(bytes, "removed-mid-upload") },
        second: -> { remove_by_client_key("removed-mid-upload") }
      )
    end

    errors = outcomes.grep(ImageAttachments::Error)
    assert_equal 1, errors.size, -> { outcomes.map { |outcome| [ outcome.class.name, outcome.inspect ] }.inspect }
    assert_equal "attachment_removed", errors.sole.code
    assert_predicate ImageAttachment.where(image_attachment_batch: @batch).sole, :removal_tombstone?
    assert_empty ActiveStorage::Blob.where("id > ?", @highest_blob_id)

    result = ImageAttachments::ClaimBatch.call(
      batch: ImageAttachmentBatch.find(@batch.id), user: @user, project: @project, parent_type: Annotation
    ) do
      @screenshot.annotations.create!(
        user: @user, x_percent: 5, y_percent: 5, comment: "Nothing attached", viewport: :desktop
      )
    end

    assert_empty result.attachments
    assert_empty ImageAttachment.where(image_attachment_batch: @batch)
  end

  test "the account byte ceiling serializes commits across different batches" do
    skip "row-lock qualification runs on PostgreSQL" unless ApplicationRecord.connection.adapter_name == "PostgreSQL"

    bytes = image_bytes
    other_batch = build_batch(user: @user, project: @project)
    parked_batch = build_batch(user: @user, project: @project)
    parked_batch.image_attachments.create!(
      user: @user,
      project: @project,
      client_key: "parked",
      state: :ready,
      media_type: "image/png",
      width: 1,
      height: 1,
      byte_size: bytes.bytesize
    )

    stub_const(ImageAttachmentBatch, :MAX_OUTSTANDING_DRAFT_BYTES, bytes.bytesize * 2) do
      outcomes = with_one_shot_instance_method_barrier(
        ImageAttachments::Ingest,
        :ensure_outstanding_drafts_within_limit!,
        predicate: ->(_record, *_args) { true }
      ) do |entered, release|
        run_blocked_race(
          entered: entered,
          release: release,
          first: -> { safe_ingest(bytes, "cap-a", batch: @batch) },
          second: -> { safe_ingest(bytes, "cap-b", batch: other_batch) }
        )
      end

      assert_equal 1, outcomes.grep(ImageAttachments::Error).size
      assert_equal "draft_storage_exhausted", outcomes.grep(ImageAttachments::Error).sole.code
      assert_equal bytes.bytesize * 2,
        ImageAttachmentBatch.outstanding_draft_bytes(@user.id)
    end
  end

  test "concurrent image comment retries converge on one complete pair" do
    bytes = image_bytes
    principal = AuthenticatedPrincipal.for_user(@user)
    operation = lambda do
      ImageAttachments::CreateApiComment.call(
        annotation: annotations(:point_annotation),
        project: @project,
        principal:,
        body: "Use this reference",
        io: StringIO.new(bytes),
        idempotency_key: "concurrent_image_comment_key_1234",
        expected_sha256: Digest::SHA256.hexdigest(bytes),
        declared_content_type: "image/png",
        declared_length: bytes.bytesize,
        filename: "upload.png"
      )
    end

    outcomes = with_one_shot_instance_method_barrier(
      ImageAttachments::PrepareUpload::Result, :stage!, predicate: ->(_record, **) { true }
    ) do |entered, release|
      run_settled_race(entered:, release:, first: operation, second: operation)
    end

    assert_no_concurrency_exceptions(outcomes)
    assert_equal %w[created replayed], outcomes.map(&:operation).sort
    assert_equal 1, outcomes.map { |result| result.comment.id }.uniq.size
    assert_equal 1, outcomes.map { |result| result.attachment.id }.uniq.size
    assert_equal 1, AnnotationComment.where("id > ?", @highest_annotation_comment_id).count
    assert_equal 1, ImageAttachment.where(annotation_comment_id: outcomes.first.comment.id).count
    assert_equal 1, ActiveStorage::Blob.where("id > ?", @highest_blob_id).count
  end

  test "a cleanup pass overlapping a submission cannot take bytes away from the message" do
    attachment = ingest_image(batch: @batch)
    @batch.update_columns(last_activity_at: 30.hours.ago, expires_at: 1.minute.ago)
    job = ImageAttachmentDraftCleanupJob.new
    listed_at = Time.current

    assert_includes job.send(:candidate_ids, listed_at, 10), @batch.id

    # The pass has already listed this draft as expired. Before it reaches the
    # candidate, the composer resumes the draft and posts it.
    outcomes = with_one_shot_instance_method_barrier(
      ImageAttachment, :update_columns, predicate: ->(record, *_args) { record.is_a?(ImageAttachment) }
    ) do |entered, release|
      run_blocked_race(
        entered: entered,
        release: release,
        first: -> { revive_and_claim },
        second: -> { job.send(:reclaim, @batch.id, listed_at) }
      )
    end

    assert_no_concurrency_exceptions(outcomes)
    claimed = outcomes.grep(ImageAttachments::ClaimBatch::Result).sole
    assert_includes outcomes, false
    assert_predicate @batch.reload, :state_claimed?
    assert_equal claimed.parent.id, attachment.reload.annotation_id
    assert attachment.image.attached?
  end

  private

  # SQLite cannot block a reader on another transaction's write, so a race that
  # resolves through an aggregate recheck is asserted by outcome rather than by
  # observed blocking. PostgreSQL runs the same interleaving with real row
  # locks in the concurrency qualification workflow.
  # An upload parked before its commit transaction holds no row lock, so the
  # racing operation can be run all the way to completion before the upload is
  # released. Waiting for it is what makes "the removal already happened" the
  # interleaving under test rather than one the faster adapter wins by luck.
  def run_settled_race(entered:, release:, first:, second:)
    first_result = Queue.new
    second_result = Queue.new
    first_thread = concurrency_thread(first_result, Queue.new, first)
    pop_with_timeout(entered)

    second_thread = concurrency_thread(second_result, Queue.new, second)
    join_with_timeout(second_thread)
    release << true
    join_with_timeout(first_thread)

    [ pop_with_timeout(first_result), pop_with_timeout(second_result) ]
  ensure
    release << true if release
    [ first_thread, second_thread ].compact.each { |thread| thread.kill if thread.alive? }
  end

  def claim_result
    ImageAttachments::ClaimBatch.call(batch: ImageAttachmentBatch.find(@batch.id), user: @user, project: @project,
      parent_type: Annotation) do
      @screenshot.annotations.create!(
        user: @user, x_percent: 10, y_percent: 10, comment: "Look here", viewport: :desktop
      )
    end
  end

  def revive_and_claim
    ImageAttachmentBatch.find(@batch.id).touch_activity!
    claim_result
  end

  def remove_by_client_key(client_key)
    row = ImageAttachment.find_by!(image_attachment_batch_id: @batch.id, client_key: client_key)
    ImageAttachments::RemoveAttachment.call(batch: ImageAttachmentBatch.find(@batch.id), attachment_id: row.id)
  end

  def safe_ingest(bytes, client_key, batch: @batch)
    ImageAttachments::Ingest.call(
      batch: ImageAttachmentBatch.find(batch.id),
      io: StringIO.new(bytes),
      client_key: client_key,
      declared_content_type: "image/png"
    )
  rescue ImageAttachments::Error => error
    error
  end
end
