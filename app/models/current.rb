# frozen_string_literal: true

class Current < ActiveSupport::CurrentAttributes
  delegate :user, :user=, :session, :session=, to: "RailsSimpleAuth::Current"
end
