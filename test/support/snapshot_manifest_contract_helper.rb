# frozen_string_literal: true

module SnapshotManifestContractHelper
  def snapshot_manifest_payload(entries: default_snapshot_entries, git_commit: "abc1234", taken_at: 2.minutes.ago.iso8601)
    normalized_time = Time.iso8601(taken_at).utc.iso8601(6)
    normalized_entries = entries.map do |entry|
      {
        page: entry.fetch(:page).strip,
        title: (entry[:title].presence || entry.fetch(:page)).strip,
        viewport: entry.fetch(:viewport).to_s.downcase,
        mime_type: entry.fetch(:mime_type).to_s.downcase,
        content_sha256: entry.fetch(:content_sha256).downcase,
        file_ref_sha256: entry.fetch(:file_ref_sha256).downcase
      }
    end
    components = [ 1, git_commit.strip.downcase, normalized_time, normalized_entries.length ]
    normalized_entries.each do |entry|
      components.concat(entry.values_at(:page, :title, :viewport, :mime_type, :content_sha256, :file_ref_sha256))
    end

    {
      version: 1,
      git_commit: git_commit,
      taken_at: taken_at,
      manifest_digest: snapshot_contract_digest("screenote-manifest-v1", components),
      entries: entries
    }
  end

  def default_snapshot_entries
    [
      snapshot_entry(page: "Public CLI Home", viewport: :desktop, seed: "home-desktop"),
      snapshot_entry(page: "Public CLI Home", viewport: :mobile, seed: "home-mobile"),
      snapshot_entry(page: "Public CLI Checkout", viewport: :desktop, seed: "checkout-desktop")
    ]
  end

  def snapshot_entry(page:, viewport:, seed:, title: nil, mime_type: "image/png")
    {
      page: page,
      title: title,
      viewport: viewport,
      mime_type: mime_type,
      content_sha256: Digest::SHA256.hexdigest("content:#{seed}"),
      file_ref_sha256: Digest::SHA256.hexdigest("path:#{seed}")
    }.compact
  end

  def snapshot_contract_digest(namespace, components)
    encoded = String.new(encoding: Encoding::BINARY)
    encoded << namespace.b << "\0"
    components.each do |component|
      value = component.to_s.encode(Encoding::UTF_8)
      encoded << value.bytesize.to_s << ":" << value.b
    end
    Digest::SHA256.hexdigest(encoded)
  end
end
