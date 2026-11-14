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
end
