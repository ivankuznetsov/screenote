# frozen_string_literal: true

namespace :screenshots do
  desc "Backfill ScreenshotImage(:desktop) rows from existing Screenshots. Use APPLY=1 to commit."
  # Do NOT run this in production until PR-2 is ready to deploy (the readers
  # must be flipped in the same deploy window). Running this in prod before
  # PR-2 will strip images off Screenshots and break the app.
  #
  # For each Screenshot with an attached image:
  # 1. Create ScreenshotImage(viewport: :desktop) with matching width/height/status
  # 2. Move the Active Storage attachment from Screenshot -> ScreenshotImage
  #    (Rails-native: detach from old record, attach same blob to new record;
  #    no S3 re-upload, no blob copy).
  #
  # Idempotent — re-running skips Screenshots that already have a desktop variant.
  task backfill_viewports: :environment do
    apply = ENV["APPLY"] == "1"
    mode = apply ? "APPLY" : "DRY-RUN"
    puts "[#{mode}] Backfilling ScreenshotImage(:desktop) rows..."
    puts "-" * 80

    stats = { already_backfilled: 0, backfilled: 0, no_image: 0, errors: 0 }

    Screenshot.find_each do |screenshot|
      if screenshot.screenshot_images.exists?(viewport: :desktop)
        stats[:already_backfilled] += 1
        next
      end

      unless screenshot.image.attached?
        # Screenshot without an image (e.g. pending upload) — create an empty
        # ScreenshotImage so the aggregate has the expected structure.
        puts "* #{label(screenshot)}: no image, creating empty desktop row"
        if apply
          screenshot.screenshot_images.create!(
            viewport: :desktop,
            status: screenshot.status,
            width: screenshot.width,
            height: screenshot.height
          )
        end
        stats[:no_image] += 1
        next
      end

      puts "+ #{label(screenshot)}: migrating blob #{screenshot.image.blob.id}"
      next unless apply

      begin
        Screenshot.transaction do
          blob = screenshot.image.blob
          screenshot.image.detach
          si = screenshot.screenshot_images.create!(
            viewport: :desktop,
            status: screenshot.status,
            width: screenshot.width,
            height: screenshot.height
          )
          si.image.attach(blob)
        end
        stats[:backfilled] += 1
      rescue StandardError => e
        puts "x #{label(screenshot)}: #{e.class}: #{e.message}"
        stats[:errors] += 1
      end
    end

    puts "-" * 80
    puts "[#{mode}] Summary: #{stats.inspect}"
    puts "Re-run with APPLY=1 to commit." unless apply
  end

  def label(screenshot)
    "Screenshot##{screenshot.id} (#{screenshot.title.truncate(40)})"
  end
end
