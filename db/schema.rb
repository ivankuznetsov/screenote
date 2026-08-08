# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_08_090000) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "admission_locks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "slot", null: false
    t.datetime "updated_at", null: false
    t.index ["slot"], name: "index_admission_locks_on_slot", unique: true
    t.check_constraint "slot >= 0 AND slot < 256", name: "admission_locks_valid_slot"
  end

  create_table "annotation_comments", force: :cascade do |t|
    t.integer "action", default: 0, null: false
    t.integer "annotation_id", null: false
    t.integer "api_key_id"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "notified_at"
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["action", "notified_at"], name: "index_annotation_comments_on_action_notified_at"
    t.index ["annotation_id", "created_at"], name: "index_annotation_comments_on_annotation_id_and_created_at"
    t.index ["annotation_id"], name: "index_annotation_comments_on_annotation_id"
    t.index ["api_key_id"], name: "index_annotation_comments_on_api_key_id"
    t.index ["user_id"], name: "index_annotation_comments_on_user_id"
    t.check_constraint "(user_id IS NOT NULL AND api_key_id IS NULL) OR (user_id IS NULL AND api_key_id IS NOT NULL)", name: "annotation_comments_exactly_one_actor"
  end

  create_table "annotations", force: :cascade do |t|
    t.integer "api_key_id"
    t.text "comment"
    t.datetime "created_at", null: false
    t.float "height_percent"
    t.integer "resolved_by_api_key_id"
    t.integer "resolved_by_user_id"
    t.integer "screenshot_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.integer "viewport", default: 0, null: false
    t.float "width_percent"
    t.float "x_percent", null: false
    t.float "y_percent", null: false
    t.index ["api_key_id"], name: "index_annotations_on_api_key_id"
    t.index ["resolved_by_api_key_id"], name: "index_annotations_on_resolved_by_api_key_id"
    t.index ["resolved_by_user_id"], name: "index_annotations_on_resolved_by_user_id"
    t.index ["screenshot_id", "status"], name: "index_annotations_on_screenshot_id_and_status"
    t.index ["screenshot_id", "viewport"], name: "index_annotations_on_screenshot_id_and_viewport"
    t.index ["screenshot_id"], name: "index_annotations_on_screenshot_id"
    t.index ["user_id"], name: "index_annotations_on_user_id"
    t.check_constraint "(status = 0 AND resolved_by_user_id IS NULL AND resolved_by_api_key_id IS NULL) OR (status = 1 AND ( (resolved_by_user_id IS NOT NULL AND resolved_by_api_key_id IS NULL) OR (resolved_by_user_id IS NULL AND resolved_by_api_key_id IS NOT NULL) ))", name: "annotations_resolution_actor_state"
    t.check_constraint "(user_id IS NOT NULL AND api_key_id IS NULL) OR (user_id IS NULL AND api_key_id IS NOT NULL)", name: "annotations_exactly_one_actor"
  end

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "issued_by_user_id"
    t.datetime "last_used_at"
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix"
    t.datetime "updated_at", null: false
    t.index ["issued_by_user_id"], name: "index_api_keys_on_issued_by_user_id"
    t.index ["project_id"], name: "index_api_keys_on_project_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
    t.check_constraint "revoked_at IS NOT NULL OR issued_by_user_id IS NOT NULL", name: "api_keys_active_requires_issuer"
  end

  create_table "authentication_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "derivation_id", limit: 64, null: false
    t.string "derivation_key_id", limit: 46, null: false
    t.datetime "expires_at", null: false
    t.bigint "generation", null: false
    t.integer "issued_by_user_id"
    t.integer "project_invitation_id"
    t.integer "purpose", null: false
    t.integer "state", default: 0, null: false
    t.datetime "terminal_at"
    t.string "token_digest", limit: 64, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id"
    t.index ["derivation_id"], name: "index_authentication_tokens_on_derivation_id", unique: true
    t.index ["issued_by_user_id", "state"], name: "index_auth_tokens_on_recovery_issuer_state", where: "purpose = 4"
    t.index ["project_invitation_id"], name: "index_authentication_tokens_on_project_invitation_id"
    t.index ["purpose", "project_invitation_id", "generation"], name: "index_auth_tokens_on_invitation_generation", unique: true, where: "project_invitation_id IS NOT NULL"
    t.index ["purpose", "project_invitation_id"], name: "index_auth_tokens_on_outstanding_invitation", unique: true, where: "state = 0 AND project_invitation_id IS NOT NULL"
    t.index ["purpose", "user_id", "generation"], name: "index_auth_tokens_on_user_generation", unique: true, where: "user_id IS NOT NULL"
    t.index ["purpose", "user_id"], name: "index_auth_tokens_on_outstanding_user", unique: true, where: "state = 0 AND user_id IS NOT NULL"
    t.index ["state", "derivation_key_id"], name: "index_authentication_tokens_on_state_and_derivation_key_id"
    t.index ["state", "expires_at"], name: "index_authentication_tokens_on_state_and_expires_at"
    t.index ["token_digest"], name: "index_authentication_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_authentication_tokens_on_user_id"
    t.check_constraint "(purpose = 0 AND project_invitation_id IS NOT NULL AND user_id IS NULL) OR (purpose IN (1, 2, 3, 4) AND user_id IS NOT NULL AND project_invitation_id IS NULL)", name: "authentication_tokens_exact_subject"
    t.check_constraint "(purpose = 4 AND issued_by_user_id IS NOT NULL) OR (purpose <> 4 AND issued_by_user_id IS NULL)", name: "authentication_tokens_recovery_issuer"
    t.check_constraint "(state = 0 AND terminal_at IS NULL) OR (state IN (1, 2, 3) AND terminal_at IS NOT NULL AND terminal_at >= created_at)", name: "authentication_tokens_terminal_state"
    t.check_constraint "expires_at > created_at", name: "authentication_tokens_future_expiry"
    t.check_constraint "generation > 0", name: "authentication_tokens_positive_generation"
    t.check_constraint "length(\"derivation_id\") = 64 AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(\"derivation_id\", '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', ''), 'a', ''), 'b', ''), 'c', ''), 'd', ''), 'e', ''), 'f', '') = ''", name: "authentication_tokens_derivation_id_length"
    t.check_constraint "length(\"derivation_key_id\") = 46 AND substr(\"derivation_key_id\", 1, 3) = 'v1.' AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(substr(\"derivation_key_id\", 4), 'A', ''), 'B', ''), 'C', ''), 'D', ''), 'E', ''), 'F', ''), 'G', ''), 'H', ''), 'I', ''), 'J', ''), 'K', ''), 'L', ''), 'M', ''), 'N', ''), 'O', ''), 'P', ''), 'Q', ''), 'R', ''), 'S', ''), 'T', ''), 'U', ''), 'V', ''), 'W', ''), 'X', ''), 'Y', ''), 'Z', ''), 'a', ''), 'b', ''), 'c', ''), 'd', ''), 'e', ''), 'f', ''), 'g', ''), 'h', ''), 'i', ''), 'j', ''), 'k', ''), 'l', ''), 'm', ''), 'n', ''), 'o', ''), 'p', ''), 'q', ''), 'r', ''), 's', ''), 't', ''), 'u', ''), 'v', ''), 'w', ''), 'x', ''), 'y', ''), 'z', ''), '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', ''), '_', ''), '-', '') = ''", name: "authentication_tokens_key_id_format"
    t.check_constraint "length(\"token_digest\") = 64 AND replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(replace(\"token_digest\", '0', ''), '1', ''), '2', ''), '3', ''), '4', ''), '5', ''), '6', ''), '7', ''), '8', ''), '9', ''), 'a', ''), 'b', ''), 'c', ''), 'd', ''), 'e', ''), 'f', '') = ''", name: "authentication_tokens_digest_length"
    t.check_constraint "purpose IN (0, 1, 2, 3, 4)", name: "authentication_tokens_valid_purpose"
    t.check_constraint "state IN (0, 1, 2, 3)", name: "authentication_tokens_valid_state"
  end

  create_table "installation_audit_events", force: :cascade do |t|
    t.integer "actor_user_id"
    t.datetime "created_at", null: false
    t.string "event_type", null: false
    t.integer "installation_id", null: false
    t.json "metadata", default: {}, null: false
    t.integer "target_user_id"
    t.index ["actor_user_id"], name: "index_installation_audit_events_on_actor_user_id"
    t.index ["installation_id"], name: "index_installation_audit_events_on_installation_id"
    t.index ["target_user_id"], name: "index_installation_audit_events_on_target_user_id"
    t.check_constraint "event_type <> '' AND event_type = LOWER(TRIM(event_type))", name: "installation_audit_events_normalized_type"
  end

  create_table "installations", force: :cascade do |t|
    t.integer "administrator_id"
    t.string "bootstrap_token_digest", limit: 64
    t.datetime "claimed_at"
    t.datetime "created_at", null: false
    t.string "deployment_mode", null: false
    t.string "singleton_key", default: "screenote", null: false
    t.string "state", null: false
    t.string "storage_namespace_fingerprint", limit: 64, null: false
    t.string "storage_service", null: false
    t.datetime "updated_at", null: false
    t.index ["administrator_id"], name: "index_installations_on_administrator_id", unique: true
    t.index ["singleton_key"], name: "index_installations_on_singleton_key", unique: true
    t.check_constraint "(deployment_mode = 'saas' AND state = 'saas' AND administrator_id IS NULL AND bootstrap_token_digest IS NULL AND claimed_at IS NULL) OR (deployment_mode = 'self_hosted' AND state = 'unclaimed' AND administrator_id IS NULL AND bootstrap_token_digest IS NOT NULL AND claimed_at IS NULL) OR (deployment_mode = 'self_hosted' AND state = 'claimed' AND administrator_id IS NOT NULL AND bootstrap_token_digest IS NULL AND claimed_at IS NOT NULL)", name: "installations_valid_state"
    t.check_constraint "(deployment_mode = 'saas' AND storage_service = 'rabata') OR (deployment_mode = 'self_hosted' AND storage_service IN ('self_hosted_local', 'self_hosted_s3'))", name: "installations_storage_service"
    t.check_constraint "bootstrap_token_digest IS NULL OR length(bootstrap_token_digest) = 64", name: "installations_bootstrap_digest"
    t.check_constraint "deployment_mode IN ('saas', 'self_hosted')", name: "installations_deployment_mode"
    t.check_constraint "length(storage_namespace_fingerprint) = 64", name: "installations_storage_fingerprint"
    t.check_constraint "singleton_key = 'screenote'", name: "installations_singleton_key"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.integer "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.string "principal_kind", null: false
    t.integer "project_id"
    t.text "redirect_uri", null: false
    t.integer "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["project_id"], name: "index_oauth_access_grants_on_project_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
    t.check_constraint "(principal_kind = 'user' AND project_id IS NULL) OR (principal_kind = 'project' AND project_id IS NOT NULL)", name: "oauth_access_grants_valid_principal"
    t.check_constraint "length(token) = 64", name: "oauth_access_grants_hashed_token"
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "principal_kind", null: false
    t.integer "project_id"
    t.string "refresh_token"
    t.integer "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["project_id"], name: "index_oauth_access_tokens_on_project_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
    t.check_constraint "(principal_kind = 'user' AND project_id IS NULL) OR (principal_kind = 'project' AND project_id IS NOT NULL)", name: "oauth_access_tokens_valid_principal"
    t.check_constraint "length(token) = 64", name: "oauth_access_tokens_hashed_token"
    t.check_constraint "previous_refresh_token = '' OR length(previous_refresh_token) = 64", name: "oauth_access_tokens_hashed_previous_refresh_token"
    t.check_constraint "refresh_token IS NULL OR length(refresh_token) = 64", name: "oauth_access_tokens_hashed_refresh_token"
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "dynamic", default: false, null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "registration_fingerprint", limit: 64
    t.string "scopes", default: "", null: false
    t.string "secret"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["registration_fingerprint"], name: "index_dynamic_oauth_apps_on_registration_fingerprint", unique: true, where: "dynamic = TRUE AND registration_fingerprint IS NOT NULL"
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
  end

  create_table "oauth_device_grants", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "denied_at"
    t.string "device_code", limit: 64, null: false
    t.datetime "expires_at", null: false
    t.datetime "last_polled_at"
    t.integer "polling_interval", default: 5, null: false
    t.string "principal_kind"
    t.integer "project_id"
    t.integer "resource_owner_id"
    t.string "scopes", null: false
    t.datetime "updated_at", null: false
    t.string "user_code", limit: 11, null: false
    t.index ["application_id"], name: "index_oauth_device_grants_on_application_id"
    t.index ["device_code"], name: "index_oauth_device_grants_on_device_code", unique: true
    t.index ["expires_at"], name: "index_oauth_device_grants_on_expires_at"
    t.index ["project_id"], name: "index_oauth_device_grants_on_project_id"
    t.index ["resource_owner_id"], name: "index_oauth_device_grants_on_resource_owner_id"
    t.index ["user_code"], name: "index_oauth_device_grants_on_user_code", unique: true
    t.check_constraint "(approved_at IS NULL AND principal_kind IS NULL AND project_id IS NULL) OR (approved_at IS NOT NULL AND resource_owner_id IS NOT NULL AND ( (principal_kind = 'user' AND project_id IS NULL) OR (principal_kind = 'project' AND project_id IS NOT NULL) ))", name: "oauth_device_grants_valid_principal"
    t.check_constraint "approved_at IS NULL OR denied_at IS NULL", name: "oauth_device_grants_single_terminal_decision"
  end

  create_table "pages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index "project_id, LOWER(name)", name: "index_pages_on_project_id_and_lower_name", unique: true
    t.index ["project_id"], name: "index_pages_on_project_id"
  end

  create_table "project_invitations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.integer "inviter_id", null: false
    t.integer "project_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index "project_id, LOWER(TRIM(email))", name: "index_project_invitations_on_pending_normalized_email", unique: true, where: "status = 0"
    t.index ["inviter_id"], name: "index_project_invitations_on_inviter_id"
    t.index ["project_id"], name: "index_project_invitations_on_project_id"
    t.check_constraint "email <> '' AND email = LOWER(TRIM(email))", name: "project_invitations_normalized_email"
    t.check_constraint "status IN (0, 1, 2)", name: "project_invitations_valid_status"
  end

  create_table "project_memberships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "project_id", null: false
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["project_id", "user_id"], name: "index_project_memberships_on_project_id_and_user_id", unique: true
    t.index ["project_id"], name: "index_project_memberships_on_project_id"
    t.index ["user_id"], name: "index_project_memberships_on_user_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "screenshot_images", force: :cascade do |t|
    t.string "content_sha256", limit: 64
    t.datetime "created_at", null: false
    t.string "expected_content_type"
    t.integer "height"
    t.integer "screenshot_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "viewport", null: false
    t.integer "width"
    t.index ["screenshot_id", "viewport"], name: "index_screenshot_images_on_screenshot_id_and_viewport", unique: true
    t.index ["screenshot_id"], name: "index_screenshot_images_on_screenshot_id"
  end

  create_table "screenshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "height"
    t.string "manifest_entry_digest", limit: 64
    t.integer "page_id", null: false
    t.integer "snapshot_id"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["created_at"], name: "index_screenshots_on_project_id_and_created_at"
    t.index ["page_id"], name: "index_screenshots_on_page_id"
    t.index ["snapshot_id", "manifest_entry_digest"], name: "idx_screenshots_snapshot_entry_digest", unique: true, where: "manifest_entry_digest IS NOT NULL"
    t.index ["snapshot_id"], name: "index_screenshots_on_snapshot_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["created_at"], name: "index_sessions_on_created_at"
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "snapshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "git_commit", limit: 40, null: false
    t.string "manifest_digest", limit: 64
    t.integer "project_id", null: false
    t.datetime "taken_at", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "manifest_digest"], name: "idx_snapshots_project_manifest_digest", unique: true, where: "manifest_digest IS NOT NULL"
    t.index ["project_id", "taken_at"], name: "index_snapshots_on_project_id_and_taken_at"
    t.index ["project_id"], name: "index_snapshots_on_project_id"
  end

  create_table "stripe_webhook_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "stripe_event_id", null: false
    t.datetime "updated_at", null: false
    t.index ["stripe_event_id"], name: "index_stripe_webhook_events_on_stripe_event_id", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.integer "plan", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.string "stripe_customer_id", null: false
    t.string "stripe_subscription_id"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["stripe_customer_id"], name: "index_subscriptions_on_stripe_customer_id", unique: true
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
    t.index ["user_id"], name: "index_subscriptions_on_user_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.integer "access_status", default: 0, null: false
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "oauth_provider"
    t.string "oauth_uid"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index "LOWER(TRIM(email))", name: "index_users_on_normalized_email", unique: true
    t.index ["confirmed_at"], name: "index_users_on_confirmed_at"
    t.index ["oauth_provider", "oauth_uid"], name: "index_users_on_oauth_identity", unique: true, where: "oauth_provider IS NOT NULL AND oauth_uid IS NOT NULL"
    t.check_constraint "(oauth_provider IS NULL AND oauth_uid IS NULL) OR (oauth_provider IS NOT NULL AND oauth_uid IS NOT NULL AND oauth_provider <> '' AND oauth_uid <> '' AND oauth_provider = LOWER(TRIM(oauth_provider)) AND oauth_uid = TRIM(oauth_uid))", name: "users_valid_oauth_identity"
    t.check_constraint "access_status IN (0, 1)", name: "users_valid_access_status"
    t.check_constraint "email <> '' AND email = LOWER(TRIM(email))", name: "users_normalized_email"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "annotation_comments", "annotations", on_delete: :cascade
  add_foreign_key "annotation_comments", "api_keys"
  add_foreign_key "annotation_comments", "users"
  add_foreign_key "annotations", "api_keys"
  add_foreign_key "annotations", "api_keys", column: "resolved_by_api_key_id"
  add_foreign_key "annotations", "screenshots"
  add_foreign_key "annotations", "users"
  add_foreign_key "annotations", "users", column: "resolved_by_user_id"
  add_foreign_key "api_keys", "projects"
  add_foreign_key "api_keys", "users", column: "issued_by_user_id"
  add_foreign_key "authentication_tokens", "project_invitations"
  add_foreign_key "authentication_tokens", "users"
  add_foreign_key "authentication_tokens", "users", column: "issued_by_user_id"
  add_foreign_key "installation_audit_events", "installations"
  add_foreign_key "installation_audit_events", "users", column: "actor_user_id"
  add_foreign_key "installation_audit_events", "users", column: "target_user_id"
  add_foreign_key "installations", "users", column: "administrator_id"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id", on_delete: :cascade
  add_foreign_key "oauth_access_grants", "projects", on_delete: :cascade
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id", on_delete: :cascade
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id", on_delete: :cascade
  add_foreign_key "oauth_access_tokens", "projects", on_delete: :cascade
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id", on_delete: :cascade
  add_foreign_key "oauth_device_grants", "oauth_applications", column: "application_id", on_delete: :cascade
  add_foreign_key "oauth_device_grants", "projects", on_delete: :cascade
  add_foreign_key "oauth_device_grants", "users", column: "resource_owner_id", on_delete: :cascade
  add_foreign_key "pages", "projects"
  add_foreign_key "project_invitations", "projects"
  add_foreign_key "project_invitations", "users", column: "inviter_id"
  add_foreign_key "project_memberships", "projects"
  add_foreign_key "project_memberships", "users"
  add_foreign_key "projects", "users"
  add_foreign_key "screenshot_images", "screenshots"
  add_foreign_key "screenshots", "pages"
  add_foreign_key "screenshots", "snapshots", on_delete: :nullify
  add_foreign_key "sessions", "users"
  add_foreign_key "snapshots", "projects"
  add_foreign_key "subscriptions", "users"
end
