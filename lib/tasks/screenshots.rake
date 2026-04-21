# frozen_string_literal: true

namespace :screenshots do
  desc "Backfill ScreenshotImage(:desktop) rows from existing Screenshots. Use APPLY=1 to commit."
  # Do NOT run this until PR-2 (reader flip) is ready to deploy in the same
  # window. Running it in production before the readers are flipped will
  # strip images off Screenshots and break the app.
  #
  # Guardrail: refuses to run unless the PR-2 reader method exists on
  # Screenshot. Remove the guard (or accept BACKFILL_FORCE=1) once PR-2 merges.
  #
  # For each Screenshot with an attached image:
  # 1. Create ScreenshotImage(viewport: :desktop) with matching width/height/status
  # 2. Move the Active Storage attachment from Screenshot -> ScreenshotImage
  #    (Rails-native: detach from old record, attach same blob to new record;
  #    no S3 re-upload, no blob copy).
  # Screenshots with no attached image are left alone — readers in PR-2 treat
  # `screenshot_images.empty?` as "no image yet" just like the pre-migration state.
  #
  # Idempotent — re-runs skip any Screenshot whose :desktop variant already
  # has its image attached.
  #
  # Rollback: after running APPLY=1, images live on ScreenshotImage, not
  # Screenshot. Reverting this PR via `rails db:rollback` DROPS the
  # screenshot_images table and with it the active_storage_attachments join
  # rows (polymorphic, no FK) — effectively orphaning blobs. Before any
  # rollback of a run backfill, invoke `rake screenshots:rollback_backfill`
  # (not included in this PR; implement before running the forward task in
  # prod if reversibility is required).
  task backfill_viewports: :environment do
    apply = ENV["APPLY"] == "1"
    force = ENV["BACKFILL_FORCE"] == "1"
    unless Screenshot.instance_methods.include?(:primary_image) || force
      abort "screenshots:backfill_viewports requires the PR-2 reader (Screenshot#primary_image). " \
            "Run with BACKFILL_FORCE=1 to bypass (only valid in tests or a coordinated PR-2 deploy)."
    end

    mode = apply ? "APPLY" : "DRY-RUN"
    puts "[#{mode}] Backfilling ScreenshotImage(:desktop) rows..."
    puts "-" * 80

    stats = { already_backfilled: 0, backfilled: 0, no_image: 0, errors: 0 }

    Screenshot.find_each do |screenshot|
      si = screenshot.screenshot_images.find_by(viewport: :desktop)

      if si&.image&.attached?
        stats[:already_backfilled] += 1
        next
      end

      unless screenshot.image.attached?
        stats[:no_image] += 1
        next
      end

      puts "+ Screenshot##{screenshot.id} (#{screenshot.title.truncate(40)}): migrating blob #{screenshot.image.blob.id}"
      next unless apply

      begin
        Screenshot.transaction do
          blob = screenshot.image.blob
          screenshot.image.detach
          si ||= screenshot.screenshot_images.create!(
            viewport: :desktop,
            status: screenshot.status,
            width: screenshot.width,
            height: screenshot.height
          )
          si.image.attach(blob)
        end
        stats[:backfilled] += 1
      rescue StandardError => e
        puts "x Screenshot##{screenshot.id}: #{e.class}: #{e.message}"
        stats[:errors] += 1
      end
    end

    puts "-" * 80
    puts "[#{mode}] Summary: #{stats.inspect}"
    puts "Re-run with APPLY=1 to commit." unless apply
  end
end
