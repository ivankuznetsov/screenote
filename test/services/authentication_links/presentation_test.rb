# frozen_string_literal: true

require "test_helper"

module AuthenticationLinks
  class PresentationTest < ActiveSupport::TestCase
    SECRET_BYTES = Base64.urlsafe_decode64("lsY9jAoyVh619LkSbaBLErWLHlSpay7RfLtaZsd-pnM")
    FRAGMENT = "v1.lsY9jAoyVh619LkSbaBLErWLHlSpay7RfLtaZsd-pnM"
    MANUAL_CODE = "v1.S3DD-3DAK-GJLB-5NPU-XEJG-3ICL-CK2Y-WHSU-VFVS-5UL4-XNNG-NR36-UZZQ"

    test "renders a credential only in a canonical-origin URL fragment" do
      presentation = Presentation.new(
        origin: "https://screenote.example",
        purpose: "invitation",
        secret_bytes: SECRET_BYTES
      )

      assert_equal FRAGMENT, presentation.fragment
      assert_equal MANUAL_CODE, presentation.manual_code
      assert_equal "https://screenote.example/authentication-links/invitation##{FRAGMENT}", presentation.url
      assert_not_includes presentation.url.split("#", 2).first, Base64.urlsafe_encode64(SECRET_BYTES, padding: false)
    end

    test "fragment and manual code decode to identical secret bytes and digest" do
      from_fragment = Presentation.decode(FRAGMENT)
      from_hash_fragment = Presentation.decode_fragment("##{FRAGMENT}")
      from_manual = Presentation.decode(MANUAL_CODE)

      assert_equal SECRET_BYTES, from_fragment.secret_bytes
      assert_equal SECRET_BYTES, from_hash_fragment.secret_bytes
      assert_equal SECRET_BYTES, from_manual.secret_bytes
      assert_equal Digest::SHA256.hexdigest(SECRET_BYTES), from_fragment.digest
      assert from_fragment.matches_digest?(from_manual.digest)
      assert_not from_fragment.matches_digest?(nil)
      assert_not from_fragment.matches_digest?("short")
      assert_not from_fragment.matches_digest?("0" * 64)
    end

    test "strictly rejects malformed or noncanonical fragments" do
      invalid = [
        "v2.#{FRAGMENT.delete_prefix('v1.')}",
        "v1.#{FRAGMENT.delete_prefix('v1.')}=",
        FRAGMENT.sub(/.$/, "N"),
        "v1.+#{FRAGMENT.delete_prefix('v1.')[1..]}",
        "v1.#{FRAGMENT.delete_prefix('v1.')[0, 42]}",
        "##{FRAGMENT}",
        " #{FRAGMENT}",
        "\xFF".b
      ]

      invalid.each do |value|
        assert_raises(Presentation::InvalidEncoding) { Presentation.decode(value) }
      end

      assert_raises(Presentation::InvalidEncoding) { Presentation.decode_fragment(FRAGMENT) }
      assert_raises(Presentation::InvalidEncoding) { Presentation.decode_fragment("#not-a-fragment") }
    end

    test "strictly rejects malformed or noncanonical manual codes" do
      invalid = [
        MANUAL_CODE.downcase,
        MANUAL_CODE.delete("-"),
        MANUAL_CODE.sub("S3DD", "S3D0"),
        MANUAL_CODE.sub(/.$/, "B"),
        MANUAL_CODE.sub("v1.", "v2."),
        " #{MANUAL_CODE}"
      ]

      invalid.each do |value|
        assert_raises(Presentation::InvalidEncoding) { Presentation.decode(value) }
      end
    end

    test "rejects noncanonical origins, unsafe purposes, and wrong secret lengths" do
      invalid_origins = [
        "https://user@screenote.example",
        "https://screenote.example/path",
        "https://screenote.example?token=value",
        "https://screenote.example#fragment",
        "javascript:alert(1)"
      ]

      invalid_origins.each do |origin|
        assert_raises(Presentation::InvalidOrigin) do
          Presentation.new(origin: origin, purpose: "invitation", secret_bytes: SECRET_BYTES)
        end
      end

      assert_raises(Presentation::InvalidOrigin) do
        Presentation.new(origin: nil, purpose: "invitation", secret_bytes: SECRET_BYTES)
      end
      assert_raises(Presentation::InvalidOrigin) do
        Presentation.new(origin: "https://[", purpose: "invitation", secret_bytes: SECRET_BYTES)
      end

      assert_raises(Presentation::InvalidPurpose) do
        Presentation.new(origin: "https://screenote.example", purpose: "../invitation", secret_bytes: SECRET_BYTES)
      end
      assert_raises(Presentation::InvalidEncoding) do
        Presentation.new(origin: "https://screenote.example", purpose: "invitation", secret_bytes: "short")
      end
    end

    test "canonicalizes root paths and IPv6 authorities without changing the safe origin" do
      root = Presentation.new(
        origin: "https://screenote.example/",
        purpose: :invitation,
        secret_bytes: SECRET_BYTES
      )
      ipv6 = Presentation.new(
        origin: "http://[::1]:3000",
        purpose: :invitation,
        secret_bytes: SECRET_BYTES
      )

      assert_equal "https://screenote.example", root.origin
      assert_equal "http://[::1]:3000", ipv6.origin
    end

    test "does not disclose bearer material through common serialization hooks" do
      presentation = Presentation.new(
        origin: "https://screenote.example",
        purpose: "invitation",
        secret_bytes: SECRET_BYTES
      )
      decoded = Presentation.decode(FRAGMENT)

      [ presentation, decoded ].each do |object|
        [ object.inspect, object.to_s, object.as_json.to_s ].each do |rendered|
          assert_includes rendered, "FILTERED"
          assert_not_includes rendered, FRAGMENT
          assert_not_includes rendered, MANUAL_CODE
        end
      end
    end
  end
end
