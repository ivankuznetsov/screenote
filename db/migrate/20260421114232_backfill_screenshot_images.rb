# frozen_string_literal: true

# Deploy-time companion to the PR-2 reader flip. Moves every attached
# Screenshot#image blob onto a new ScreenshotImage(viewport: :desktop) in the
# same deploy window that makes the new reader code live, so there is no
# gap where readers expect ScreenshotImage but blobs still sit on Screenshot.
#
# Delegates to ScreenshotImage.backfill_from_screenshots! — same logic the
# operator-facing `rake screenshots:backfill_viewports` calls. Idempotent:
# running multiple times, or running the rake task after this migration, is
# a no-op on Screenshots already backfilled.
#
# Error handling: completes as much as it can. Reports the summary via `say`
# and exits cleanly even if individual records errored; operators run the
# rake task to retry stragglers rather than retrying the whole migration.
# A total-failure case (zero progress) raises — something is systematically
# wrong and the deploy should not proceed.
#
# To reverse: run `rake screenshots:rollback_backfill APPLY=1` to move blobs
# back onto Screenshot, THEN `rails db:rollback STEP=1`. Running rollback
# without first moving blobs orphans them (AS attachments are polymorphic).
class BackfillScreenshotImages < ActiveRecord::Migration[8.1]
  def up
    result = ScreenshotImage.backfill_from_screenshots!(apply: true, logger: StringIO.new.tap { |io| @log = io })
    say @log.string unless @log.string.empty?
    say "ScreenshotImage backfill: #{result.to_h.inspect}"

    if result.errors.positive? && result.backfilled.zero? && result.already_backfilled.zero?
      raise "ScreenshotImage backfill made zero progress with #{result.errors} errors — aborting migration. " \
            "Investigate and re-run `rake screenshots:backfill_viewports APPLY=1`."
    end

    return unless result.errors.positive?

    say "#{result.errors} records errored. Run `rake screenshots:backfill_viewports APPLY=1` " \
        "post-deploy to retry stragglers (task is idempotent)."
  end

  def down
    result = ScreenshotImage.rollback_to_screenshots!(apply: true, logger: StringIO.new.tap { |io| @log = io })
    say @log.string unless @log.string.empty?
    say "ScreenshotImage rollback: #{result.to_h.inspect}"
    raise "Rollback reported errors — inspect manually" if result.errors.positive?
  end
end
