# frozen_string_literal: true

require "test_helper"

class AuthenticationTokenTest < ActiveSupport::TestCase
  setup do
    @user = users(:alice)
    @invitation = project_invitations(:pending_invitation)
  end

  test "binds invitations and user purposes to their exact subject type" do
    invitation_token = build_token(purpose: :invitation, subject: @invitation)
    assert invitation_token.valid?
    assert_equal @invitation, invitation_token.subject
    assert_equal "ProjectInvitation", invitation_token.subject_type
    assert_equal @invitation.id, invitation_token.subject_id

    %i[password_reset magic_link email_confirmation account_recovery].each do |purpose|
      token = build_token(purpose: purpose, subject: @user)
      assert token.valid?, -> { "#{purpose}: #{token.errors.full_messages.to_sentence}" }
      assert_equal @user, token.subject
      assert_equal "User", token.subject_type
      assert_equal @user.id, token.subject_id
    end

    assert_not build_token(purpose: :invitation, subject: @user).valid?
    assert_not build_token(purpose: :password_reset, subject: @invitation).valid?
  end

  test "rejects unsupported and missing subjects without inventing a subject identity" do
    token = build_token(purpose: :password_reset, subject: @user)

    error = assert_raises(ArgumentError) { token.subject = Object.new }
    assert_equal "authentication token subject must be a User or ProjectInvitation", error.message

    token.user = nil
    assert_nil token.subject
    assert_nil token.subject_type
    assert_nil token.subject_id
    assert_not token.valid?
    assert_includes token.errors[:base], "purpose must be bound to its exact subject type"

    token.user = @user
    token.purpose = nil
    assert_not token.valid?
    assert_includes token.errors[:base], "purpose must be bound to its exact subject type"
  end

  test "stores only a digest and immutable public derivation metadata" do
    token = build_token(purpose: :password_reset, subject: @user)
    token.save!

    assert_equal [], token.attribute_names.grep(/raw|plaintext|credential|secret/)
    assert_equal [ "token_digest" ], token.attribute_names.grep(/token/)
    assert_raises(ActiveRecord::ReadonlyAttributeError) do
      token.update!(derivation_id: "f" * 64)
    end
  end

  test "atomically moves from outstanding to one terminal state" do
    token = build_token(purpose: :password_reset, subject: @user)
    token.save!

    assert token.active?
    assert token.transition_to!(:consumed)
    assert token.consumed?
    assert token.terminal?
    assert token.terminal_at.present?
    assert_not token.transition_to!(:cancelled)
    assert token.reload.consumed?
    assert_raises(ArgumentError) do
      build_token(purpose: :magic_link, subject: @user).tap(&:save!)
        .transition_to!(:cancelled, at: 1.minute.ago)
    end

    assert_raises(ArgumentError) do
      build_token(purpose: :email_confirmation, subject: @user).tap(&:save!)
        .transition_to!(:outstanding)
    end
  end

  test "reports active and expired lifecycle boundaries without accepting a missing expiry" do
    token = build_token(purpose: :password_reset, subject: @user)
    assert_not token.expired?

    token.expires_at = 1.second.ago
    assert token.expired?
    assert_not token.active?

    token.expires_at = nil
    assert_not token.expired?
    assert_not token.active?
    assert_not token.valid?
    assert_includes token.errors[:expires_at], "must be present"
  end

  test "requires terminal_at to agree with state" do
    token = build_token(purpose: :password_reset, subject: @user,
      state: :consumed, terminal_at: nil)
    assert_not token.valid?

    token.state = :outstanding
    token.terminal_at = Time.current
    assert_not token.valid?

    token.state = :consumed
    token.terminal_at = token.created_at - 1.second
    assert_not token.valid?
    assert_includes token.errors[:terminal_at], "must match token state"
  end

  test "rejects malformed key fingerprints and expiry at or before creation" do
    token = build_token(purpose: :password_reset, subject: @user)
    token.derivation_key_id = "v1.#{'A' * 42}."
    assert_not token.valid?

    token.derivation_key_id = "v1.#{'A' * 43}"
    token.expires_at = token.created_at
    assert_not token.valid?
  end

  test "allows only one outstanding generation for a subject and purpose" do
    build_token(purpose: :password_reset, subject: @user, generation: 1).save!

    duplicate = build_token(purpose: :password_reset, subject: @user, generation: 2)
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save!(validate: false) }
  end

  private

  def build_token(purpose:, subject:, generation: 1, state: :outstanding, terminal_at: nil)
    now = Time.current
    AuthenticationToken.new(
      purpose: purpose,
      subject: subject,
      issued_by_user: (@user if purpose.to_sym == :account_recovery),
      generation: generation,
      derivation_id: SecureRandom.hex(32),
      derivation_key_id: "v1.#{Base64.urlsafe_encode64(SecureRandom.random_bytes(32), padding: false)}",
      token_digest: SecureRandom.hex(32),
      expires_at: now + 15.minutes,
      state: state,
      terminal_at: terminal_at,
      created_at: now,
      updated_at: now
    )
  end
end
