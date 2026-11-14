# frozen_string_literal: true

# Historical data migration from the April 2026 multi-viewport rollout. It
# moved every legacy Screenshot#image blob onto a ScreenshotImage(:desktop)
# through application helpers that have since been removed together with
# Screenshot#image itself.
#
# Every existing database has already run it and new databases load
# db/schema.rb, so `up` is intentionally a no-op. A database migrated from
# scratch has no legacy screenshots to move.
#
# `down` used to move blobs back onto Screenshot#image before the
# screenshot_images table could be dropped. That target no longer exists, so
# rolling back past this point is refused rather than left to orphan every
# ScreenshotImage attachment.
class BackfillScreenshotImages < ActiveRecord::Migration[8.1]
  def up
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Screenshot#image no longer exists; ScreenshotImage blobs cannot be moved back"
  end
end
