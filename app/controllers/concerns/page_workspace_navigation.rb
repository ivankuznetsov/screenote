# frozen_string_literal: true

module PageWorkspaceNavigation
  extend ActiveSupport::Concern

  included do
    helper_method :page_workspace_path_for
  end

  private

  def page_workspace_path_for(screenshot, viewport: nil, **query)
    page_path(screenshot.page_id, **page_workspace_options(screenshot, viewport: viewport, **query))
  end

  # The query a workspace deep link needs, without committing to a path or a
  # URL helper. Mail builds an absolute URL from the same options, so the digest
  # call to action and every in-app link cannot validate viewports differently.
  def page_workspace_options(screenshot, viewport: nil, **query)
    options = { version_id: screenshot.id }
    validated_viewport = validated_workspace_viewport(screenshot, viewport)
    options[:viewport] = validated_viewport if validated_viewport
    options.merge!(query.compact)
    options
  end

  def page_workspace_viewport_for(screenshot, requested_viewport)
    validated_workspace_viewport(screenshot, requested_viewport) || screenshot.default_viewport
  end

  def validated_workspace_viewport(screenshot, viewport)
    requested = viewport.to_s.presence
    requested if screenshot.available_viewports.include?(requested)
  end
end
