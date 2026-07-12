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

ActiveRecord::Schema[8.1].define(version: 2026_07_12_153000) do
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
  end

  create_table "annotations", force: :cascade do |t|
    t.text "comment"
    t.datetime "created_at", null: false
    t.float "height_percent"
    t.integer "resolved_by_api_key_id"
    t.integer "resolved_by_user_id"
    t.integer "screenshot_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.integer "viewport", default: 0, null: false
    t.float "width_percent"
    t.float "x_percent", null: false
    t.float "y_percent", null: false
    t.index ["resolved_by_api_key_id"], name: "index_annotations_on_resolved_by_api_key_id"
    t.index ["resolved_by_user_id"], name: "index_annotations_on_resolved_by_user_id"
    t.index ["screenshot_id", "status"], name: "index_annotations_on_screenshot_id_and_status"
    t.index ["screenshot_id", "viewport"], name: "index_annotations_on_screenshot_id_and_viewport"
    t.index ["screenshot_id"], name: "index_annotations_on_screenshot_id"
    t.index ["user_id"], name: "index_annotations_on_user_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.string "token_prefix"
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_api_keys_on_project_id"
    t.index ["token_digest"], name: "index_api_keys_on_token_digest", unique: true
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.integer "application_id", null: false
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
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
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.integer "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.integer "project_id"
    t.string "refresh_token"
    t.integer "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["project_id"], name: "index_oauth_access_tokens_on_project_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: false, null: false
    t.datetime "created_at", null: false
    t.boolean "dynamic", default: false, null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret"
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
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
    t.index ["inviter_id"], name: "index_project_invitations_on_inviter_id"
    t.index ["project_id", "email", "status"], name: "index_project_invitations_on_project_id_and_email_and_status"
    t.index ["project_id"], name: "index_project_invitations_on_project_id"
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
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.string "oauth_provider"
    t.string "oauth_uid"
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["confirmed_at"], name: "index_users_on_confirmed_at"
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "annotation_comments", "annotations", on_delete: :cascade
  add_foreign_key "annotation_comments", "api_keys", on_delete: :nullify
  add_foreign_key "annotation_comments", "users", on_delete: :nullify
  add_foreign_key "annotations", "api_keys", column: "resolved_by_api_key_id", on_delete: :nullify
  add_foreign_key "annotations", "screenshots"
  add_foreign_key "annotations", "users"
  add_foreign_key "annotations", "users", column: "resolved_by_user_id", on_delete: :nullify
  add_foreign_key "api_keys", "projects"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id", on_delete: :cascade
  add_foreign_key "oauth_access_grants", "projects", on_delete: :nullify
  add_foreign_key "oauth_access_grants", "users", column: "resource_owner_id", on_delete: :cascade
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id", on_delete: :cascade
  add_foreign_key "oauth_access_tokens", "projects", on_delete: :nullify
  add_foreign_key "oauth_access_tokens", "users", column: "resource_owner_id", on_delete: :cascade
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
