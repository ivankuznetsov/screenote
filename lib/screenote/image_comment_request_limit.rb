# frozen_string_literal: true

require "json"

module Screenote
  # Bounds the dedicated multipart image-comment route before Rack parses it.
  class ImageCommentRequestLimit
    MULTIPART_OVERHEAD = 1.megabyte
    TARGET_PATH = %r{\A/api/v1/annotations/[^/]+/image_comments(?:\.[^/]+)?\z}

    class TooLarge < StandardError; end

    class LimitedInput
      def initialize(input, max_bytes:)
        @input = input
        @max_bytes = max_bytes
        @consumed = 0
      end

      def read(length = nil, outbuf = nil)
        requested = length.nil? ? remaining_with_sentinel : [ length, remaining_with_sentinel ].min
        chunk = outbuf ? input.read(requested, outbuf) : input.read(requested)
        account!(chunk)
      end

      def readpartial(length, outbuf = nil)
        requested = [ length, remaining_with_sentinel ].min
        chunk = outbuf ? input.readpartial(requested, outbuf) : input.readpartial(requested)
        account!(chunk)
      end

      def gets(separator = $INPUT_RECORD_SEPARATOR, limit = nil, chomp: false)
        return read(limit) if separator.nil?

        maximum = [ limit || remaining_with_sentinel, remaining_with_sentinel ].min
        line = input.gets(separator, maximum)
        return unless line

        account!(line)
        chomp ? line.chomp(separator) : line
      end

      def each
        return enum_for(:each) unless block_given?

        while (line = gets)
          yield line
        end
        self
      end
      alias_method :each_line, :each

      def rewind
        input.rewind
        @consumed = 0
        0
      end

      def close
        input.close
      end

      def closed?
        input.closed?
      end

      def eof?
        input.eof?
      end

      private

      attr_reader :input, :max_bytes, :consumed

      def remaining_with_sentinel
        max_bytes - consumed + 1
      end

      def account!(chunk)
        return chunk unless chunk

        @consumed += chunk.bytesize
        raise TooLarge if consumed > max_bytes

        chunk
      end
    end

    def self.max_request_size
      ImageAttachment::MAX_FILE_SIZE + MULTIPART_OVERHEAD
    end

    def initialize(app, max_bytes: nil)
      @app = app
      @max_bytes = max_bytes
    end

    def call(env)
      return app.call(env) unless targeted?(env)
      return too_large_response if declared_length(env) > max_bytes

      env["rack.input"] = LimitedInput.new(env.fetch("rack.input"), max_bytes: max_bytes)
      app.call(env)
    rescue TooLarge
      too_large_response
    end

    private

    attr_reader :app

    def max_bytes
      @max_bytes || self.class.max_request_size
    end

    def targeted?(env)
      env["REQUEST_METHOD"] == "POST" && TARGET_PATH.match?(env["PATH_INFO"].to_s)
    end

    def declared_length(env)
      Integer(env["CONTENT_LENGTH"].to_s, 10, exception: false) || 0
    end

    def too_large_response
      body = JSON.generate(error: "Image comment request is too large", code: "request_too_large")
      [
        413,
        {
          "Content-Type" => "application/json; charset=utf-8",
          "Content-Length" => body.bytesize.to_s,
          "Cache-Control" => "no-store"
        },
        [ body ]
      ]
    end
  end
end
