# frozen_string_literal: true

module InstanceAdministration
  class Authority
    Locked = Data.define(:installation, :administrator, :actor, :target)

    class << self
      # Call only inside the operation's outer transaction. Installation is
      # always locked before users, and users are locked in ascending ID order.
      def lock(actor:, target: nil)
        installation = Installation.lock.find_by(singleton_key: Installation::SINGLETON_KEY)
        return Locked.new(installation: nil, administrator: nil, actor: nil, target: nil) unless installation

        user_ids = [ installation.administrator_id, actor&.id, target&.id ].compact.uniq
        users = User.where(id: user_ids).to_a
        locked_users = AuthorityLock.users!(users).index_by(&:id)

        Locked.new(
          installation: installation,
          administrator: locked_users[installation.administrator_id],
          actor: locked_users[actor&.id],
          target: locked_users[target&.id]
        )
      end

      def available?(locked)
        installation = locked.installation
        installation&.valid? && installation.self_hosted? && installation.claimed? &&
          locked.administrator&.active?
      end

      def authorized?(locked, operator: false)
        return false unless available?(locked)
        return true if operator

        locked.actor&.active? && locked.actor.id == locked.administrator.id
      end
    end
  end
end
