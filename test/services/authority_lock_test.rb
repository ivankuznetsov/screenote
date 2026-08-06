# frozen_string_literal: true

require "test_helper"

class AuthorityLockTest < ActiveSupport::TestCase
  class LockableUser
    Connection = Data.define(:adapter_name)

    attr_reader :id

    def self.connection
      @connection ||= Connection.new(adapter_name: "PostgreSQL")
    end

    def initialize(id:, lock_order:, persisted: true)
      @id = id
      @lock_order = lock_order
      @persisted = persisted
    end

    def persisted?
      @persisted
    end

    def lock!
      @lock_order << id
      self
    end
  end

  class MissingSQLiteUser
    Connection = Data.define(:adapter_name)
    Relation = Data.define(:updated) do
      def update_all(*)
        updated
      end
    end

    attr_reader :id

    def self.connection
      Connection.new(adapter_name: "SQLite")
    end

    def self.where(id:)
      Relation.new(updated: id == -1 ? 0 : 1)
    end

    def initialize(id:)
      @id = id
    end

    def reload
      self
    end
  end

  test "locks unique users in ascending ID order" do
    lock_order = []
    higher_id = LockableUser.new(id: 20, lock_order: lock_order)
    lower_id = LockableUser.new(id: 10, lock_order: lock_order)

    locked_users = AuthorityLock.users!(higher_id, lower_id, higher_id)

    assert_equal [ 10, 20 ], lock_order
    assert_equal [ 10, 20 ], locked_users.map(&:id)
  end

  test "validates every user before taking the first lock" do
    lock_order = []
    persisted = LockableUser.new(id: 10, lock_order: lock_order)
    unpersisted = LockableUser.new(id: nil, lock_order: lock_order, persisted: false)

    assert_raises(ActiveRecord::RecordNotFound) do
      AuthorityLock.users!(persisted, unpersisted)
    end

    assert_empty lock_order
  end

  test "rejects a missing user before trying to lock it" do
    assert_raises(ActiveRecord::RecordNotFound) { AuthorityLock.user!(nil) }
  end

  test "fails closed when a SQLite authority row disappears before its no-op write" do
    assert_raises(ActiveRecord::RecordNotFound) do
      AuthorityLock.user!(MissingSQLiteUser.new(id: -1))
    end
  end
end
