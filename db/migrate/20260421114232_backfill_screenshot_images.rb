# frozen_string_literal: true

# Deploy-time companion to the PR-2 reader flip. Moves every attached
# Screenshot#image blob onto a new ScreenshotImage(viewport: :desktop) in the
# same transaction that makes the new reader code live, so there is no window
# where readers expect ScreenshotImage but blobs still sit on Screenshot.
#
# Delegates to ScreenshotImageBackfillService (same logic the operator-facing
# `rake screenshots:backfill_viewports` calls). Idempotent: running this
# migration multiple times, or running the rake task after the migration, is
# a no-op on Screenshots already backfilled.
#
# To reverse: run `rake screenshots:rollback_backfill APPLY=1` to move blobs
# back onto Screenshot, THEN `rails db:rollback STEP=1`. Running rollback
# without first moving blobs orphans them (AS attachments are polymorphic,
# no FK cascade).
class BackfillScreenshotImages < ActiveRecord::Migration[8.1]
  def up
    result = ScreenshotImageBackfillService.apply!(logger: StringIO.new)
    say "ScreenshotImage backfill: #{result.to_h.inspect}"
    if result.errors.positive?
      raise "ScreenshotImage backfill reported #{result.errors} errors — aborting migration. " \
            "Run `rake screenshots:backfill_viewports APPLY=1` manually to inspect."
    end
  end

  def down
    result = ScreenshotImageRollbackService.apply!(logger: StringIO.new)
    say "ScreenshotImage rollback: #{result.to_h.inspect}"
    raise "Rollback reported errors — inspect manually" if result.errors.positive?
  end
end
