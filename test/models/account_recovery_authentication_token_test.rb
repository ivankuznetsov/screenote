# frozen_string_literal: true

require "test_helper"

class AccountRecoveryAuthenticationTokenTest < ActiveSupport::TestCase
  setup do
    @issuer = users(:alice)
    @subject = users(:bob)
  end

  test "account recovery requires immutable issuer provenance" do
    token = build_token(issued_by_user: @issuer)

    assert token.valid?
    token.save!

    assert_equal @issuer.id, token.issued_by_user_id
    assert_raises(ActiveRecord::ReadonlyAttributeError) do
      token.issued_by_user = users(:admin)
    end
  end

  test "account recovery rejects missing issuer provenance before persistence" do
    missing = build_token

    assert_not missing.valid?
    assert_includes missing.errors[:issued_by_user], "must be present"
  end

  test "non recovery authentication tokens reject issuer provenance" do
    token = build_token(purpose: :password_reset, issued_by_user: @issuer)

    assert_not token.valid?
    assert_includes token.errors[:issued_by_user], "is only valid for account recovery"
  end

  test "database constraints require recovery issuer and reject it for other purposes" do
    now = Time.current
    attributes = token_attributes(now: now)

    assert_raises(ActiveRecord::StatementInvalid) do
      AuthenticationToken.insert_all!([ attributes.merge(issued_by_user_id: nil) ])
    end

    assert_raises(ActiveRecord::StatementInvalid) do
      AuthenticationToken.insert_all!([ attributes.merge(
        purpose: AuthenticationToken.purposes.fetch("password_reset"),
        issued_by_user_id: @issuer.id,
        derivation_id: "b" * 64,
        token_digest: "c" * 64
      ) ])
    end
  end

  private

  def build_token(purpose: :account_recovery, issued_by_user: nil)
    AuthenticationToken.new(
      token_attributes(now: Time.current).merge(
        purpose: purpose,
        issued_by_user: issued_by_user
      )
    )
  end

  def token_attributes(now:)
    {
      purpose: AuthenticationToken.purposes.fetch("account_recovery"),
      user_id: @subject.id,
      project_invitation_id: nil,
      generation: 1,
      derivation_id: "a" * 64,
      derivation_key_id: "v1.#{'d' * 43}",
      token_digest: "e" * 64,
      expires_at: now + 15.minutes,
      state: AuthenticationToken.states.fetch("outstanding"),
      terminal_at: nil,
      created_at: now,
      updated_at: now
    }
  end
end
