# frozen_string_literal: true

class CreateSnapshotTool < ApplicationTool
  tool_name "create_snapshot"
  description "Create a project snapshot record for a capture run. Pass the returned snapshot_id into create_multi_viewport_screenshot."

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:git_commit).filled(:string).description("Short or full git commit hash, 7-40 hex characters; case is normalized to lowercase")
    optional(:taken_at).filled(:string).description("ISO 8601 datetime with offset (e.g., 2026-05-14T12:00:00Z); bare dates like 2026-05-14 are rejected. Defaults to now.")
  end

  def call(project_id:, git_commit:, taken_at: nil)
    error = require_project(project_id)
    return error if error

    normalized_commit = git_commit.to_s.downcase
    return invalid("git_commit must be 7-40 hex characters") unless normalized_commit.match?(Snapshot::GIT_COMMIT_FORMAT)

    if taken_at
      snapshot_taken_at = parse_taken_at(taken_at)
      return invalid("taken_at must be an ISO 8601 timestamp") unless snapshot_taken_at
    else
      snapshot_taken_at = Time.current
    end

    with_error_handling do
      snapshot = current_project.snapshots.create!(git_commit: normalized_commit, taken_at: snapshot_taken_at)

      {
        snapshot_id: snapshot.id,
        project_id: snapshot.project_id,
        label: snapshot.label,
        taken_at: snapshot.taken_at.iso8601
      }.to_json
    end
  end

  private

  def parse_taken_at(taken_at)
    Time.iso8601(taken_at).in_time_zone
  rescue ArgumentError
    nil
  end
end
