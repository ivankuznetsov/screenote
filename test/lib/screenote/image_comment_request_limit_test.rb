# frozen_string_literal: true

require "test_helper"

class Screenote::ImageCommentRequestLimitTest < ActiveSupport::TestCase
  test "rejects a declared oversized image comment without calling the app" do
    called = false
    middleware = build_middleware(8) do
      called = true
      ok_response
    end

    status, headers, body = middleware.call(environment("123456789", content_length: 9))

    assert_equal 413, status
    assert_equal "application/json; charset=utf-8", headers.fetch("Content-Type")
    assert_equal "no-store", headers.fetch("Cache-Control")
    assert_equal "request_too_large", JSON.parse(body.join).fetch("code")
    assert_not called
  end

  test "bounds every trailing-slash alias that Rails routes to image comment creation" do
    paths = %w[
      /api/v1/annotations/12/image_comments/
      /api/v1/annotations/12/image_comments//
      /api/v1/annotations/12/image_comments.json/
    ]

    paths.each do |path|
      called = false
      middleware = build_middleware(8) do
        called = true
        ok_response
      end

      status, _headers, body = middleware.call(environment("123456789", path:, content_length: 9))

      assert_equal 413, status, path
      assert_equal "request_too_large", JSON.parse(body.join).fetch("code"), path
      assert_not called, path
    end
  end

  test "bounds chunked trailing-slash aliases while the parser reads" do
    paths = %w[
      /api/v1/annotations/12/image_comments/
      /api/v1/annotations/12/image_comments//
      /api/v1/annotations/12/image_comments.json/
    ]

    paths.each do |path|
      middleware = build_middleware(8) do |env|
        env.fetch("rack.input").read
        ok_response
      end

      status, _headers, body = middleware.call(environment("123456789", path:))

      assert_equal 413, status, path
      assert_equal "request_too_large", JSON.parse(body.join).fetch("code"), path
    end
  end

  test "bounds a chunked body while the downstream parser reads it" do
    middleware = build_middleware(8) do |env|
      env.fetch("rack.input").read
      ok_response
    end

    status, _headers, body = middleware.call(environment("123456789"))

    assert_equal 413, status
    assert_equal "request_too_large", JSON.parse(body.join).fetch("code")
  end

  test "gets accounts for a separator byte before chomping" do
    middleware = build_middleware(8) do |env|
      env.fetch("rack.input").gets(chomp: true)
      ok_response
    end

    status, _headers, body = middleware.call(environment("12345678\n"))

    assert_equal 413, status
    assert_equal "request_too_large", JSON.parse(body.join).fetch("code")
  end

  test "readpartial accounts for reads with and without an output buffer" do
    input = Screenote::ImageCommentRequestLimit::LimitedInput.new(StringIO.new("123456789"), max_bytes: 8)
    output = +"stale"

    assert_equal "1234", input.readpartial(4, output)
    assert_equal "1234", output
    assert_equal "5678", input.readpartial(4)
    assert_raises(Screenote::ImageCommentRequestLimit::TooLarge) { input.readpartial(1) }
  end

  test "preserves line enumeration and closeable IO behavior" do
    input = Screenote::ImageCommentRequestLimit::LimitedInput.new(StringIO.new("one\ntwo\n"), max_bytes: 8)
    chomped = Screenote::ImageCommentRequestLimit::LimitedInput.new(StringIO.new("one\n"), max_bytes: 4)

    assert_equal "one", chomped.gets(chomp: true)
    assert_equal "one\ntwo\n", input.gets(nil)
    assert_predicate input, :eof?

    input.rewind
    assert_instance_of Enumerator, input.each
    assert_equal [ "one\n", "two\n" ], input.each.to_a
    assert_predicate input, :eof?

    input.close
    assert_predicate input, :closed?
  end

  test "allows an exact-limit body and preserves rewind behavior" do
    observed = []
    middleware = build_middleware(8) do |env|
      input = env.fetch("rack.input")
      observed << input.read
      input.rewind
      observed << input.read
      ok_response
    end

    status, = middleware.call(environment("12345678", content_length: 8))

    assert_equal 200, status
    assert_equal %w[12345678 12345678], observed
  end

  test "does not wrap unrelated routes" do
    input_class = nil
    middleware = build_middleware(2) do |env|
      input_class = env.fetch("rack.input").class
      env.fetch("rack.input").read
      ok_response
    end
    env = environment("unbounded", path: "/api/v1/annotations/1/comments")

    status, = middleware.call(env)

    assert_equal 200, status
    assert_equal StringIO, input_class
  end

  private

  def build_middleware(max_bytes, &app)
    Screenote::ImageCommentRequestLimit.new(app, max_bytes: max_bytes)
  end

  def environment(body, path: "/api/v1/annotations/12/image_comments", content_length: nil)
    {
      "REQUEST_METHOD" => "POST",
      "PATH_INFO" => path,
      "rack.input" => StringIO.new(body),
      "CONTENT_LENGTH" => content_length&.to_s
    }
  end

  def ok_response
    [ 200, { "Content-Type" => "text/plain" }, [ "ok" ] ]
  end
end
