# frozen_string_literal: true

class AddInstallationBootstrapDigestConstraint < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :installations,
      "bootstrap_token_digest IS NULL OR length(bootstrap_token_digest) = 64",
      name: "installations_bootstrap_digest"
  end
end
