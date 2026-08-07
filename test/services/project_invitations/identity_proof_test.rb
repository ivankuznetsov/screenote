# frozen_string_literal: true

require "test_helper"

module ProjectInvitations
  class IdentityProofTest < ActiveSupport::TestCase
    test "builds an immutable session proof without retaining the user record" do
      proof = IdentityProof.session(user: users(:alice))

      assert proof.session?
      assert proof.valid?
      assert_equal users(:alice).id, proof.user_id
      assert_nil proof.password
      assert proof.frozen?

      assert_not IdentityProof.session(user: User.new).valid?
    end

    test "keeps local credentials out of inspection and serialization" do
      password = "private-password"
      proof = IdentityProof.local(password: password, password_confirmation: password)

      assert proof.local?
      assert proof.valid?
      assert_equal password, proof.password
      assert_equal password, proof.password_confirmation
      assert_includes proof.inspect, "FILTERED"
      assert_not_includes proof.inspect, password
      assert_equal "[FILTERED]", proof.as_json
      assert_equal proof.inspect, proof.to_s

      returned_password = proof.password
      returned_password.replace("changed")
      assert_equal password, proof.password
    end

    test "requires Google to assert a verified normalized email" do
      proof = IdentityProof.provider(
        "provider" => "google_oauth2",
        "uid" => "google-123",
        "info" => { "email" => " Invitee@Example.test ", "email_verified" => true }
      )

      assert proof.provider?
      assert proof.valid?
      assert_equal "invitee@example.test", proof.verified_email
      assert_equal "google_oauth2", proof.provider_name
      assert_equal "google-123", proof.provider_uid

      unverified = IdentityProof.provider(
        "provider" => "google_oauth2",
        "uid" => "google-123",
        "info" => { "email" => "invitee@example.test", "email_verified" => "true" }
      )
      assert_not unverified.valid?
    end

    test "requires GitHub's primary verified address to equal the normalized info email" do
      proof = IdentityProof.provider(
        "provider" => "github",
        "uid" => "github-123",
        "info" => { "email" => "Invitee@Example.test" },
        "extra" => {
          "all_emails" => [
            { "email" => "other@example.test", "primary" => false, "verified" => true },
            { "email" => "invitee@example.test", "primary" => true, "verified" => true }
          ]
        }
      )

      assert proof.valid?
      assert_equal "invitee@example.test", proof.verified_email

      mismatched = IdentityProof.provider(
        "provider" => "github",
        "uid" => "github-123",
        "info" => { "email" => "invitee@example.test" },
        "extra" => {
          "all_emails" => [
            { "email" => "different@example.test", "primary" => true, "verified" => true }
          ]
        }
      )
      assert_not mismatched.valid?
    end

    test "rejects unsupported and malformed provider payloads" do
      assert_not IdentityProof.provider({}).valid?
      assert_not IdentityProof.provider(
        "provider" => "gitlab",
        "uid" => "uid",
        "info" => { "email" => "invitee@example.test" }
      ).valid?
      assert_not IdentityProof.provider(
        "provider" => "github",
        "uid" => " ",
        "info" => { "email" => "invitee@example.test" },
        "extra" => { "all_emails" => [] }
      ).valid?
    end

    test "handles absent local confirmation and rejects unsupported proof kinds" do
      proof = IdentityProof.local(password: "password", password_confirmation: nil)

      assert proof.valid?
      assert_nil proof.password_confirmation
      assert_raises(ArgumentError) do
        IdentityProof.new(kind: :future, valid: true)
      end
    end

    test "rejects non-hash provider structures and malformed GitHub email collections" do
      assert_not IdentityProof.provider(Object.new).valid?

      malformed_emails = IdentityProof.provider(
        provider: "github",
        uid: "github-123",
        info: { email: "invitee@example.test" },
        extra: { all_emails: { email: "invitee@example.test" } }
      )
      assert_not malformed_emails.valid?

      symbol_payload = IdentityProof.provider(
        provider: "github",
        uid: "github-symbols",
        info: { email: "Invitee@Example.test" },
        extra: {
          all_emails: [
            { email: "invitee@example.test", primary: true, verified: true }
          ]
        }
      )
      assert symbol_payload.valid?
      assert_equal "invitee@example.test", symbol_payload.verified_email
    end

    test "fails closed for missing malformed and unverified GitHub addresses" do
      missing_info_email = IdentityProof.provider(
        provider: "github",
        uid: "github-missing-email",
        extra: { all_emails: [] }
      )
      malformed_info_email = IdentityProof.provider(
        provider: "github",
        uid: "github-malformed-email",
        info: { email: "not-an-email" },
        extra: {
          all_emails: [ { email: "not-an-email", primary: true, verified: true } ]
        }
      )
      unverified_primary = IdentityProof.provider(
        provider: "github",
        uid: "github-unverified",
        info: { email: "invitee@example.test" },
        extra: {
          all_emails: [ { email: "invitee@example.test", primary: true, verified: false } ]
        }
      )

      assert_not missing_info_email.valid?
      assert_not malformed_info_email.valid?
      assert_not unverified_primary.valid?
    end

    test "fails closed when string and symbol provider keys conflict" do
      conflicting_verification = IdentityProof.provider(
        "provider" => "google_oauth2",
        "uid" => "google-conflicting-verification",
        "info" => {
          "email" => "invitee@example.test",
          "email_verified" => false,
          email_verified: true
        }
      )
      conflicting_provider = IdentityProof.provider(
        "provider" => "gitlab",
        provider: "google_oauth2",
        "uid" => "google-conflicting-provider",
        "info" => { "email" => "invitee@example.test", "email_verified" => true }
      )

      assert_not conflicting_verification.valid?
      assert_not conflicting_provider.valid?
    end

    test "accepts indexable provider payloads without key predicates" do
      payload_class = Struct.new(:provider, :uid, :info)
      payload = payload_class.new(
        "google_oauth2",
        "google-indexable",
        { "email" => "invitee@example.test", "email_verified" => true }
      )

      proof = IdentityProof.provider(payload)

      assert proof.valid?
      assert_equal "google-indexable", proof.provider_uid
    end
  end
end
