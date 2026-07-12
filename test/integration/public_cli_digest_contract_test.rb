# frozen_string_literal: true

require "test_helper"

class PublicCliDigestContractTest < ActiveSupport::TestCase
  test "Rails executes the canonical digest vectors published by the public CLI" do
    fixture_path = ENV["SCREENOTE_CLI_CONTRACT_PATH"].presence
    skip "SCREENOTE_CLI_CONTRACT_PATH is not set" unless fixture_path

    fixture = JSON.parse(File.read(fixture_path))
    assert_equal Snapshots::PrepareUpload::VERSION, fixture.fetch("version")

    %w[manifest group].each do |name|
      vector = fixture.fetch(name)
      actual = Snapshots::PrepareUpload.digest(vector.fetch("namespace"), vector.fetch("components"))

      assert_equal vector.fetch("sha256"), actual, "#{name} digest drifted from the public CLI contract"
    end

    payload = fixture.fetch("semantic_manifest").merge(
      "manifest_digest" => fixture.dig("manifest", "sha256")
    )
    result = Snapshots::PrepareUpload.call(project: projects(:alice_project), payload: payload)

    assert result.created
    assert_equal fixture.dig("manifest", "sha256"), result.snapshot.manifest_digest
    assert_equal fixture.dig("group", "sha256"), result.snapshot.screenshots.sole.manifest_entry_digest
  end
end
