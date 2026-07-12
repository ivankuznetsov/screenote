# frozen_string_literal: true

module Snapshots
  class EnsureProcessing
    class << self
      def call(snapshot:)
        new(snapshot:).call
      end
    end

    def initialize(snapshot:)
      @snapshot = snapshot
    end

    def call
      snapshot.screenshot_images
        .status_pending
        .joins(:image_attachment)
        .preload(:image_attachment)
        .find_each(&:ensure_dimension_processing)
    end

    private

    attr_reader :snapshot
  end
end
