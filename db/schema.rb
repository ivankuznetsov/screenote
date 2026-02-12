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

ActiveRecord::Schema[8.1].define(version: 2026_02_12_071517) do
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
    t.float "width_percent"
    t.float "x_percent", null: false
    t.float "y_percent", null: false
    t.index ["resolved_by_api_key_id"], name: "index_annotations_on_resolved_by_api_key_id"
    t.index ["resolved_by_user_id"], name: "index_annotations_on_resolved_by_user_id"
    t.index ["screenshot_id", "status"], name: "index_annotations_on_screenshot_id_and_status"
    t.index ["screenshot_id"], name: "index_annotations_on_screenshot_id"
    t.index ["user_id"], name: "index_annotations_on_user_id"
  end

  create_table "api_keys", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.integer "project_id", null: false
    t.datetime "revoked_at"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_api_keys_on_project_id"
    t.index ["token"], name: "index_api_keys_on_token", unique: true
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "screenshots", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "height"
    t.integer "project_id", null: false
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.integer "width"
    t.index ["project_id"], name: "index_screenshots_on_project_id"
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
  add_foreign_key "annotations", "api_keys", column: "resolved_by_api_key_id"
  add_foreign_key "annotations", "screenshots"
  add_foreign_key "annotations", "users"
  add_foreign_key "annotations", "users", column: "resolved_by_user_id"
  add_foreign_key "api_keys", "projects"
  add_foreign_key "projects", "users"
  add_foreign_key "screenshots", "projects"
  add_foreign_key "sessions", "users"
end
