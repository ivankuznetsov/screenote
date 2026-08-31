# frozen_string_literal: true

# One streaming contract for every protected blob response.
#
# Active Storage's public routes stay disabled: nothing here redirects to the
# storage provider, and no durable or provider-signed URL ever leaves the
# application. The caller authorizes the read first; this only decides how the
# already-authorized bytes go out, and they are never cached anywhere.
module BlobStreaming
  extend ActiveSupport::Concern

  included do
    include ActiveStorage::Streaming
  end

  private

  # Shared variant resolution for every protected media route. An
  # authenticated GET never invokes libvips: a variant the warming job has not
  # produced yet simply is not available, and `raw` names the variants that are
  # served straight from the original blob.
  def resolve_variant_blob(attached, variant_name, allowed:, raw: %w[original])
    return nil unless attached.attached?
    return attached.blob if raw.include?(variant_name)

    variant_key = allowed[variant_name]
    return nil unless variant_key

    attached.variant(variant_key).image&.blob
  end

  def stream_blob(blob, disposition: :inline)
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"

    if request.headers["Range"].present?
      send_blob_byte_range_data(blob, request.headers["Range"], disposition: disposition)
    else
      response.headers["Accept-Ranges"] = "bytes"
      response.headers["Content-Length"] = blob.byte_size.to_s
      send_blob_stream(blob, disposition: disposition)
    end
  end
end
