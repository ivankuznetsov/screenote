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
    @batch = build_batch
  end

  teardown do
    ImageAttachment.delete_all
    ImageAttachmentBatch.delete_all
    Annotation.where.not(id: Annotation.pluck(:id) & fixture_annotation_ids).delete_all
    ActiveStorage::Blob.find_each(&:purge) if ActiveStorage::Blob.exists?
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
      run_barriered_race(
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

  private

  # SQLite cannot block a reader on another transaction's write, so a race that
  # resolves through an aggregate recheck is asserted by outcome rather than by
  # observed blocking. PostgreSQL runs the same interleaving with real row
  # locks in the concurrency qualification workflow.
  def run_barriered_race(entered:, release:, first:, second:)
    first_result = Queue.new
    second_result = Queue.new
    first_thread = concurrency_thread(first_result, Queue.new, first)
    pop_with_timeout(entered)

    second_thread = concurrency_thread(second_result, Queue.new, second)
    release << true
    join_with_timeout(second_thread)
    join_with_timeout(first_thread)

    [ pop_with_timeout(first_result), pop_with_timeout(second_result) ]
  ensure
    [ first_thread, second_thread ].compact.each { |thread| thread.kill if thread.alive? }
  end

  def fixture_annotation_ids
    @fixture_annotation_ids ||= %i[point_annotation region_annotation resolved_annotation bob_annotation]
      .map { |name| annotations(name).id }
  end

  def claim_result
    ImageAttachments::ClaimBatch.call(batch: ImageAttachmentBatch.find(@batch.id), user: @user, project: @project) do
      @screenshot.annotations.create!(
        user: @user, x_percent: 10, y_percent: 10, comment: "Look here", viewport: :desktop
      )
    end
  end

  def safe_ingest(bytes, client_key)
    ImageAttachments::Ingest.call(
      batch: ImageAttachmentBatch.find(@batch.id),
      io: StringIO.new(bytes),
      client_key: client_key,
      declared_content_type: "image/png"
    )
  rescue ImageAttachments::Error => error
    error
  end
end
