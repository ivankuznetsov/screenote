# frozen_string_literal: true

module SingletonMethodStubHelper
  def with_singleton_method(receiver, name, replacement)
    original = receiver.method(name)
    receiver.define_singleton_method(name, replacement)
    yield
  ensure
    receiver.define_singleton_method(name, original) if original
  end

  alias_method :with_singleton_method_stub, :with_singleton_method
end
