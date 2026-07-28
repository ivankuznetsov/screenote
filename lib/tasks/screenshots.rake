# frozen_string_literal: true

namespace :screenshots do
  desc "Warm named overview thumbnails. Dry-run by default; use APPLY=1 to process."
  task warm_thumbnails: :environment do
    apply = ENV["APPLY"] == "1"
    batch_size = Integer(ENV.fetch("BATCH_SIZE", "1000"))
    mode = apply ? "APPLY" : "DRY-RUN"
    puts "[#{mode}] Warming current primary screenshot thumbnails..."
    puts "-" * 80

    result = ScreenshotImage.warm_thumbnails!(apply: apply, batch_size: batch_size)

    puts "-" * 80
    puts "[#{mode}] Summary: #{result.to_h.inspect}"
    puts "Re-run with APPLY=1 to process." unless apply
  end

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
