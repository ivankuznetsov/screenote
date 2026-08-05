# frozen_string_literal: true

require "test_helper"

class AuthorizedMediaDeliveryTest < ActionDispatch::IntegrationTest
  setup do
    @image = screenshot_images(:alice_screenshot_desktop)
    @bytes = file_fixture("test_image.png").binread
    @image.image.attach(
      io: StringIO.new(@bytes),
      filename: "private.png",
      content_type: "image/png"
    )
  end

  teardown do
    @image.image.purge if @image.image.attached?
  end

  test "default Active Storage delivery routes are not drawn" do
    route_names = Rails.application.routes.named_routes.names.map(&:to_s)

    %w[
      rails_service_blob
      rails_service_blob_proxy
      rails_blob_representation
      rails_blob_representation_proxy
      rails_disk_service
      update_rails_disk_service
      rails_direct_uploads
    ].each { |route_name| assert_not_includes route_names, route_name }
  end

  test "an active project member receives original bytes through the application" do
    sign_in(users(:alice))

    get "/media/screenshot_images/#{@image.id}/original"

    assert_response :ok
    assert_equal "image/png", response.media_type
    assert_equal @bytes, response.body
    assert_nil response.headers["Location"]
    assert_match(/private/, response.headers["Cache-Control"])
    assert_equal "bytes", response.headers["Accept-Ranges"]
    assert_equal @bytes.bytesize.to_s, response.headers["Content-Length"]
  end

  test "an active project member receives bounded byte ranges through the application" do
    sign_in(users(:alice))

    get "/media/screenshot_images/#{@image.id}/original", headers: { "Range" => "bytes=0-15" }

    assert_response :partial_content
    assert_equal @bytes.byteslice(0, 16), response.body
    assert_equal "bytes 0-15/#{@bytes.bytesize}", response.headers["Content-Range"]
    assert_equal "bytes", response.headers["Accept-Ranges"]
    assert_nil response.headers["Location"]
  end

  test "logged-out and foreign users cannot reuse a known media URL" do
    get "/media/screenshot_images/#{@image.id}/original"
    assert_redirected_to new_session_path

    sign_in(users(:admin))
    get "/media/screenshot_images/#{@image.id}/original"
    assert_response :not_found
  end

  test "membership is rechecked for every request" do
    bob = users(:bob)
    membership = project_memberships(:bob_member_of_alice_project)
    sign_in(bob)

    get "/media/screenshot_images/#{@image.id}/original"
    assert_response :ok

    membership.destroy!
    get "/media/screenshot_images/#{@image.id}/original"
    assert_response :not_found
  end

  test "an authorized member receives a preprocessed named variant without a provider redirect" do
    require_vips!
    variant = @image.image.variant(:project_strip).processed
    expected = variant.download
    sign_in(users(:alice))

    get "/media/screenshot_images/#{@image.id}/project_strip"

    assert_response :ok
    assert_equal expected, response.body
    assert_nil response.headers["Location"]
  end
end
