# frozen_string_literal: true

class AuthorityLock
  class << self
    def users!(*users)
      users = users.flatten
      raise ActiveRecord::RecordNotFound if users.any? { |user| !user&.persisted? }

      users
        .uniq(&:id)
        .sort_by(&:id)
        .map { |user| user!(user) }
    end

    def user!(user)
      raise ActiveRecord::RecordNotFound unless user&.persisted?

      if user.class.connection.adapter_name.casecmp?("SQLite")
        # SQLite ignores SELECT ... FOR UPDATE. A no-op write makes this the
        # transaction's first authority statement and acquires its database
        # writer lock until credential issuance or membership removal commits.
        updated = user.class.where(id: user.id).update_all(updated_at: Arel.sql("updated_at"))
        raise ActiveRecord::RecordNotFound unless updated == 1

        user.reload
      else
        user.lock!
      end
    end
  end
end
