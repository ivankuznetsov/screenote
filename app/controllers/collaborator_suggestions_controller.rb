# frozen_string_literal: true

class CollaboratorSuggestionsController < ApplicationController
  include ProjectAuthorization

  before_action :set_project
  before_action :require_owner!

  rate_limit to: 30, within: 1.minute

  def index
    query = params[:q].to_s.strip.downcase
    return head :no_content if query.length < 2

    exclude_emails = @project.members.pluck(:email) +
                     @project.project_invitations.pending.pluck(:email) +
                     [ Current.user.email ]

    other_project_ids = Current.user.project_memberships
                                    .where.not(project_id: @project.id)
                                    .select(:project_id)

    sanitized = ActiveRecord::Base.sanitize_sql_like(query)
    @suggestions = User.joins(:project_memberships)
                       .where(project_memberships: { project_id: other_project_ids })
                       .where.not(email: exclude_emails)
                       .where("LOWER(email) LIKE ?", "%#{sanitized}%")
                       .distinct
                       .limit(8)

    render partial: "collaborator_suggestions/suggestions", layout: false
  end
end
