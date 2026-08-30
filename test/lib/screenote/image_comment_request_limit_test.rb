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
