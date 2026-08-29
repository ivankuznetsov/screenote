# frozen_string_literal: true

module ImageAttachments
  # Machine code plus actionable text. Controllers surface both; the code is
  # what the composer branches on, and `retryable` tells it whether the same
  # bytes are worth sending again.
  class Error < StandardError
    RETRYABLE_CODES = %w[decoder_busy storage_unavailable].freeze

    attr_reader :code, :status

    def initialize(message, code:, status: :unprocessable_entity)
      super(message)
      @code = code.to_s
      @status = status
    end

    def retryable?
      RETRYABLE_CODES.include?(code)
    end
  end
end
