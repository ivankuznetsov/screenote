# frozen_string_literal: true

namespace :screenshots do
  desc "Backfill ScreenshotImage(:desktop) rows from existing Screenshots. Use APPLY=1 to commit."
  # Operator entry point for the blob-move backfill. The same logic is called
  # by the PR-2 deploy-time migration so this task is primarily useful for:
  #   - Dry-run sanity check before a coordinated deploy
  #   - Catch-up pass if a Screenshot was created after the deploy migration
  #     ran but before its image attachment settled
  # See ScreenshotImageBackfillService for implementation details.
  task backfill_viewports: :environment do
    apply = ENV["APPLY"] == "1"
    mode = apply ? "APPLY" : "DRY-RUN"
    puts "[#{mode}] Backfilling ScreenshotImage(:desktop) rows..."
    puts "-" * 80

    result = ScreenshotImageBackfillService.new(apply: apply).call

    puts "-" * 80
    puts "[#{mode}] Summary: #{result.to_h.inspect}"
    puts "Re-run with APPLY=1 to commit." unless apply
  end

  desc "Move ScreenshotImage(:desktop) blobs back onto their Screenshot. Use APPLY=1 to commit."
  # Reverse of backfill_viewports. Use before rolling back PR-2 in prod if the
  # forward backfill has already run — otherwise `rails db:rollback` drops the
  # screenshot_images table and orphans the blobs (AS attachments are
  # polymorphic, no FK, no cascade).
  task rollback_backfill: :environment do
    apply = ENV["APPLY"] == "1"
    mode = apply ? "APPLY" : "DRY-RUN"
    puts "[#{mode}] Rolling back: moving ScreenshotImage(:desktop) blobs back to Screenshot..."
    puts "-" * 80

    result = ScreenshotImageRollbackService.new(apply: apply).call

    puts "-" * 80
    puts "[#{mode}] Summary: #{result.to_h.inspect}"
    puts "Re-run with APPLY=1 to commit." unless apply
  end
end
