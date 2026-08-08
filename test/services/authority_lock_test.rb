# frozen_string_literal: true

require "test_helper"

class AuthorityLockTest < ActiveSupport::TestCase
  class LockableUser
    Connection = Data.define(:transaction_open?)

    class Relation
      def initialize(id, lock_order)
        @id = id
        @lock_order = lock_order
      end

      def update_all(*)
        @lock_order << @id
        1
      end
    end

    class << self
      attr_accessor :lock_order

      def connection
        Connection.new(transaction_open?: true)
      end

      def where(id:)
        Relation.new(id, lock_order)
      end
    end

    attr_reader :id

    def initialize(id:, lock_order:, persisted: true)
      @id = id
      @persisted = persisted
      self.class.lock_order = lock_order
    end

    def persisted?
      @persisted
    end

    def reload
      self
    end
  end

  class OutsideTransactionUser < LockableUser
    def self.connection
      Connection.new(transaction_open?: false)
    end
  end

  class MissingUser
    Connection = Data.define(:transaction_open?)
    Relation = Data.define(:updated) do
      def update_all(*)
        updated
      end
    end

    attr_reader :id

    def self.connection
      Connection.new(transaction_open?: true)
    end

    def self.where(id:)
      Relation.new(updated: id == -1 ? 0 : 1)
    end

    def initialize(id:)
      @id = id
    end

    def persisted?
      true
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

  test "rejects a non-persisted user before trying to lock it" do
    lock_order = []
    user = LockableUser.new(id: 10, lock_order: lock_order, persisted: false)

    assert_raises(ActiveRecord::RecordNotFound) { AuthorityLock.user!(user) }
    assert_empty lock_order
  end

  test "fails before issuing SQL when no outer transaction is open" do
    lock_order = []
    user = OutsideTransactionUser.new(id: 10, lock_order: lock_order)

    assert_raises(AuthorityLock::OutsideTransaction) { AuthorityLock.user!(user) }
    assert_empty lock_order
  end

  test "fails closed when an authority row disappears before its no-op write" do
    assert_raises(ActiveRecord::RecordNotFound) do
      AuthorityLock.user!(MissingUser.new(id: -1))
    end
  end
end
