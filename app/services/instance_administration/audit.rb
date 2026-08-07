# frozen_string_literal: true

module InstanceAdministration
  class Audit
    CHANNEL_PATTERN = /\A[a-z0-9_]{1,32}\z/

    class << self
      def write!(installation:, event_type:, actor: nil, target: nil, channel: "web", metadata: {})
        InstallationAuditEvent.create!(
          installation: installation,
          actor_user: actor,
          target_user: target,
          event_type: event_type,
          metadata: bounded_metadata(metadata).merge("channel" => normalize_channel(channel))
        )
      end

      def denied!(installation:, actor:, target:, action:, reason:, channel: "web")
        return unless actor&.persisted?

        write!(
          installation: installation,
          actor: actor,
          target: target,
          event_type: "instance_action_denied",
          channel: channel,
          metadata: { "action" => action.to_s, "reason" => reason.to_s }
        )
      end

      private

      def normalize_channel(value)
        normalized = value.to_s.strip.downcase
        CHANNEL_PATTERN.match?(normalized) ? normalized : "unknown"
      end

      def bounded_metadata(metadata)
        metadata.to_h.each_with_object({}) do |(key, value), result|
          key = key.to_s.first(64)
          result[key] = case value
          when Integer, TrueClass, FalseClass, NilClass
            value
          else
            value.to_s.first(128)
          end
        end
      end
    end
  end
end
