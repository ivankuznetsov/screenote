# frozen_string_literal: true

module AuthenticationLinks
  class KeyringPreflight
    class MissingKey < StandardError; end

    class << self
      def call(keyring: Runtime.keyring, connection: AuthenticationToken.connection)
        return true unless connection.data_source_exists?(AuthenticationToken.table_name)

        missing = AuthenticationToken.active
          .where.not(derivation_key_id: keyring.key_ids)
          .exists?
        if missing
          raise MissingKey,
            "an active authentication link requires an unavailable prior derivation key"
        end

        true
      end
    end
  end
end
