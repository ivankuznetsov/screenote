# frozen_string_literal: true

abort "self-hosted identity preload is test-only" unless ENV["RAILS_ENV"] == "test"

require_relative "../../lib/screenote/self_hosted/host_operations"

module Screenote
  module SelfHosted
    module HostOperations
      remove_const(:SUPPORTED_UID)
      const_set(:SUPPORTED_UID, Process.uid)
      remove_const(:SUPPORTED_GID)
      const_set(:SUPPORTED_GID, Process.gid)
    end
  end
end
