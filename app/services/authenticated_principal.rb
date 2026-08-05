# frozen_string_literal: true

class AuthenticatedPrincipal
  READ_SCOPE = "mcp_read"
  WRITE_SCOPE = "mcp_write"
  API_KEY_SCOPES = [ READ_SCOPE, WRITE_SCOPE ].freeze
  KINDS = %i[user project].freeze

  attr_reader :kind, :user, :issuer, :project, :api_key, :oauth_token, :scopes

  class << self
    def for_user(user)
      return unless active_user?(user)

      new(kind: :user, user: user, issuer: user, scopes: API_KEY_SCOPES)
    end

    def for_api_key(api_key)
      return if api_key.nil? || api_key.revoked?

      project = api_key.project
      issuer = api_key.issued_by_user
      return if project.nil? || !active_user?(issuer)

      new(
        kind: :project,
        user: nil,
        issuer: issuer,
        project: project,
        api_key: api_key,
        scopes: API_KEY_SCOPES
      )
    end

    def for_oauth_token(oauth_token)
      return if oauth_token.nil? || oauth_token.revoked? || oauth_token.expired?

      user = User.find_by(id: oauth_token.resource_owner_id)
      return unless active_user?(user)

      kind = oauth_token.principal_kind&.to_sym
      return unless KINDS.include?(kind)

      project = oauth_project_for(oauth_token, user, kind)
      return if kind == :project && project.nil?
      return if kind == :user && oauth_token.project_id.present?

      new(
        kind: kind,
        user: user,
        issuer: user,
        project: project,
        oauth_token: oauth_token,
        scopes: oauth_token.scopes
      )
    end

    private

    def active_user?(user)
      user.present? && (!user.respond_to?(:active?) || user.active?)
    end

    def oauth_project_for(oauth_token, user, kind)
      return if kind == :user
      return if oauth_token.project_id.blank?

      user.projects.find_by(id: oauth_token.project_id)
    end
  end

  def initialize(kind:, user:, issuer:, scopes:, project: nil, api_key: nil, oauth_token: nil)
    @kind = kind.to_sym
    @user = user
    @issuer = issuer
    @project = project
    @api_key = api_key
    @oauth_token = oauth_token
    @scopes = normalize_scopes(scopes)
    freeze
  end

  def user_principal?
    kind == :user
  end

  def project_principal?
    kind == :project
  end

  def api_key?
    api_key.present?
  end

  def oauth?
    oauth_token.present?
  end

  def browser?
    !api_key? && !oauth?
  end

  def scope?(scope)
    scopes.include?(scope.to_s)
  end

  alias_method :allows_scope?, :scope?

  def read?
    scope?(READ_SCOPE)
  end

  def write?
    scope?(WRITE_SCOPE)
  end

  def project_access?(candidate)
    return false if candidate.nil?

    if project_principal?
      return false unless project&.id == candidate.id

      api_key? || user.projects.exists?(id: candidate.id)
    else
      user.projects.exists?(id: candidate.id)
    end
  end

  def resolve_project(project_id)
    if project_principal?
      return project if project && (project_id.blank? || project.id.to_s == project_id.to_s) && project_access?(project)

      return nil
    end

    return nil if project_id.blank?

    user.projects.find_by(id: project_id)
  end

  def can_create_project?
    user_principal? && user.present? && write?
  end

  def can_invite_to?(candidate)
    !api_key? && user.present? && write? && project_access?(candidate) && candidate.owner?(user)
  end

  def annotation_actor_attributes
    api_key? ? { user: nil, api_key: api_key } : { user: user, api_key: nil }
  end

  private

  def normalize_scopes(value)
    Array(value.respond_to?(:to_a) ? value.to_a : value.to_s.split).map(&:to_s).uniq.sort.freeze
  end
end
