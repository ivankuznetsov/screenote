# frozen_string_literal: true

namespace :screenshots do
  desc "Backfill ScreenshotImage(:desktop) rows from existing Screenshots. Use APPLY=1 to commit."
  task backfill_viewports: :environment do
    apply = ENV["APPLY"] == "1"
    mode = apply ? "APPLY" : "DRY-RUN"
    puts "[#{mode}] Backfilling ScreenshotImage(:desktop) rows..."
    puts "-" * 80

    result = ScreenshotImage.backfill_from_screenshots!(apply: apply)

    puts "-" * 80
    puts "[#{mode}] Summary: #{result.to_h.inspect}"
    puts "Re-run with APPLY=1 to commit." unless apply
  end

  desc "Move ScreenshotImage(:desktop) blobs back onto their Screenshot. Use APPLY=1 to commit."
  # Reverse of backfill_viewports. Use before rolling back the multi-viewport
  # feature in prod — otherwise `rails db:rollback` drops the screenshot_images
  # table and orphans the blobs (AS attachments are polymorphic, no FK cascade).
  task rollback_backfill: :environment do
    apply = ENV["APPLY"] == "1"
    mode = apply ? "APPLY" : "DRY-RUN"
    puts "[#{mode}] Rolling back: moving ScreenshotImage(:desktop) blobs back to Screenshot..."
    puts "-" * 80

    result = ScreenshotImage.rollback_to_screenshots!(apply: apply)

    puts "-" * 80
    puts "[#{mode}] Summary: #{result.to_h.inspect}"
    puts "Re-run with APPLY=1 to commit." unless apply
  end
end
