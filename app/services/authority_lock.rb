# frozen_string_literal: true

class AuthorityLock
  class OutsideTransaction < StandardError; end

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
      unless user.class.connection.transaction_open?
        raise OutsideTransaction, "authority locks require an open outer transaction"
      end

      updated = user.class.where(id: user.id).update_all(updated_at: Arel.sql("updated_at"))
      raise ActiveRecord::RecordNotFound unless updated == 1

      user.reload
    end
  end
end
