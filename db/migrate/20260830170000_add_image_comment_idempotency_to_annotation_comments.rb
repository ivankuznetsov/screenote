# frozen_string_literal: true

class AddImageCommentIdempotencyToAnnotationComments < ActiveRecord::Migration[8.1]
  HEX_CHARACTERS = "0123456789abcdef"
  RECEIPT_PAIR_CHECK = <<~SQL.squish.freeze
    (idempotency_fingerprint IS NULL AND request_digest IS NULL) OR
    (idempotency_fingerprint IS NOT NULL AND request_digest IS NOT NULL)
  SQL

  def change
    add_column :annotation_comments, :idempotency_fingerprint, :string, limit: 64
    add_column :annotation_comments, :request_digest, :string, limit: 64

    add_index :annotation_comments, :idempotency_fingerprint,
      unique: true,
      where: "idempotency_fingerprint IS NOT NULL",
      name: "index_annotation_comments_on_idempotency_fingerprint"

    add_check_constraint :annotation_comments, RECEIPT_PAIR_CHECK,
      name: "annotation_comments_idempotency_pair"
    add_check_constraint :annotation_comments, digest_pair_format_check,
      name: "annotation_comments_idempotency_format"
  end

  private

  def digest_pair_format_check
    fingerprint = connection.quote_column_name(:idempotency_fingerprint)
    request = connection.quote_column_name(:request_digest)
    <<~SQL.squish
      (#{fingerprint} IS NULL AND #{request} IS NULL) OR
      (#{hex_check(fingerprint)} AND #{hex_check(request)})
    SQL
  end

  def hex_check(expression)
    "length(#{expression}) = 64 AND #{strip_characters(expression, HEX_CHARACTERS)} = ''"
  end

  def strip_characters(expression, allowed_characters)
    allowed_characters.each_char.reduce(expression) do |remaining, character|
      "replace(#{remaining}, #{connection.quote(character)}, '')"
    end
  end
end
