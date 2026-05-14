# frozen_string_literal: true

class CreateSnapshotTool < ApplicationTool
  tool_name "create_snapshot"
  description "Create a project snapshot record for a capture run. Pass the returned snapshot_id into create_multi_viewport_screenshot."

  GIT_COMMIT_PATTERN = /\A[0-9a-fA-F]{7,40}\z/

  arguments do
    required(:project_id).filled(:integer).description("The project ID")
    required(:git_commit).filled(:string).description("Short or full git commit hash, 7-40 hex characters")
    optional(:taken_at).filled(:string).description("ISO 8601 timestamp for when the snapshot was taken; defaults to now")
  end

  def call(project_id:, git_commit:, taken_at: nil)
    error = require_project(project_id)
    return error if error

    return invalid("git_commit must be 7-40 hex characters") unless git_commit.match?(GIT_COMMIT_PATTERN)

    snapshot_taken_at = parse_taken_at(taken_at)
    return invalid("taken_at must be an ISO 8601 timestamp") unless snapshot_taken_at

    with_error_handling do
      snapshot = current_project.snapshots.create!(git_commit: git_commit, taken_at: snapshot_taken_at)

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
    return Time.current unless taken_at

    Time.iso8601(taken_at).in_time_zone
  rescue ArgumentError
    nil
  end

  def invalid(message)
    { error: "invalid_arguments", message: message }.to_json
  end
end
