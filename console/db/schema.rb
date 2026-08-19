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

ActiveRecord::Schema[8.1].define(version: 2026_08_19_120000) do
  create_table "apps", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.json "env", default: [], null: false
    t.string "health"
    t.string "name", null: false
    t.integer "port"
    t.json "release", default: [], null: false
    t.json "secret_files", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_apps_on_name", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor", null: false
    t.datetime "at", null: false
    t.datetime "created_at", null: false
    t.text "detail"
    t.datetime "finished_at"
    t.integer "install_id"
    t.integer "machine_id"
    t.string "outcome"
    t.integer "project_id"
    t.json "raw", default: {}, null: false
    t.string "summary"
    t.datetime "updated_at", null: false
    t.index ["at"], name: "index_events_on_at"
    t.index ["install_id"], name: "index_events_on_install_id"
    t.index ["machine_id"], name: "index_events_on_machine_id"
    t.index ["project_id"], name: "index_events_on_project_id"
  end

  create_table "install_targets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "current_image"
    t.string "desired_image"
    t.integer "install_id", null: false
    t.integer "machine_id", null: false
    t.integer "position", default: 0, null: false
    t.string "status", default: "pending", null: false
    t.string "strategy", default: "single", null: false
    t.datetime "updated_at", null: false
    t.index ["install_id", "machine_id"], name: "index_install_targets_on_install_id_and_machine_id", unique: true
    t.index ["install_id"], name: "index_install_targets_on_install_id"
    t.index ["machine_id"], name: "index_install_targets_on_machine_id"
  end

  create_table "installs", force: :cascade do |t|
    t.integer "app_id"
    t.integer "balancer_id"
    t.json "config", default: {}, null: false
    t.integer "count", default: 1, null: false
    t.datetime "created_at", null: false
    t.string "exposure", default: "edge", null: false
    t.string "health"
    t.string "hostname"
    t.string "image"
    t.string "name", null: false
    t.integer "port"
    t.integer "project_id"
    t.datetime "updated_at", null: false
    t.integer "version_id"
    t.index ["app_id"], name: "index_installs_on_app_id"
    t.index ["balancer_id"], name: "index_installs_on_balancer_id"
    t.index ["project_id"], name: "index_installs_on_project_id"
    t.index ["version_id"], name: "index_installs_on_version_id"
  end

  create_table "labels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key", null: false
    t.integer "labelable_id", null: false
    t.string "labelable_type", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["key", "value"], name: "index_labels_on_key_and_value"
    t.index ["labelable_type", "labelable_id", "key"], name: "index_labels_on_labelable_and_key", unique: true
    t.index ["labelable_type", "labelable_id"], name: "index_labels_on_labelable"
  end

  create_table "machine_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "machine_id", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["machine_id", "project_id"], name: "index_machine_grants_on_machine_id_and_project_id", unique: true
    t.index ["machine_id"], name: "index_machine_grants_on_machine_id"
    t.index ["project_id"], name: "index_machine_grants_on_project_id"
  end

  create_table "machines", force: :cascade do |t|
    t.boolean "balancer", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "last_seen_at"
    t.string "name", null: false
    t.integer "owner_id"
    t.string "scope", default: "observe", null: false
    t.string "sharing", default: "dedicated", null: false
    t.string "ssh_host", null: false
    t.integer "ssh_port", default: 22, null: false
    t.text "ssh_private_key"
    t.text "ssh_public_key"
    t.string "ssh_user", default: "root", null: false
    t.string "status", default: "unknown", null: false
    t.string "steward_version"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_machines_on_name", unique: true
    t.index ["owner_id"], name: "index_machines_on_owner_id"
  end

  create_table "project_machines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "machine_id", null: false
    t.integer "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["machine_id"], name: "index_project_machines_on_machine_id"
    t.index ["project_id", "machine_id"], name: "index_project_machines_on_project_id_and_machine_id", unique: true
    t.index ["project_id"], name: "index_project_machines_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.string "contact_email"
    t.string "contact_name"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.boolean "starred", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_projects_on_name", unique: true
    t.index ["starred"], name: "index_projects_on_starred"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "installs_library_only", default: true, null: false
    t.datetime "updated_at", null: false
  end

  create_table "snapshots", force: :cascade do |t|
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.integer "machine_id", null: false
    t.json "metrics", default: {}, null: false
    t.json "raw", default: {}, null: false
    t.boolean "reachable", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["machine_id", "captured_at"], name: "index_snapshots_on_machine_id_and_captured_at"
    t.index ["machine_id"], name: "index_snapshots_on_machine_id"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", limit: 4, null: false
    t.datetime "created_at", null: false
    t.binary "key", limit: 1024, null: false
    t.integer "key_hash", limit: 8, null: false
    t.binary "value", limit: 536870912, null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "mode", default: "system", null: false
    t.string "password_digest", null: false
    t.string "theme", default: "steward", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "versions", force: :cascade do |t|
    t.integer "app_id", null: false
    t.datetime "created_at", null: false
    t.string "image", null: false
    t.boolean "latest", default: false, null: false
    t.string "tag", null: false
    t.datetime "updated_at", null: false
    t.index ["app_id", "tag"], name: "index_versions_on_app_id_and_tag", unique: true
    t.index ["app_id"], name: "index_versions_on_app_id"
    t.index ["app_id"], name: "index_versions_one_latest_per_app", unique: true, where: "latest"
  end

  add_foreign_key "events", "installs"
  add_foreign_key "events", "machines"
  add_foreign_key "events", "projects"
  add_foreign_key "install_targets", "installs"
  add_foreign_key "install_targets", "machines"
  add_foreign_key "installs", "apps"
  add_foreign_key "installs", "machines", column: "balancer_id"
  add_foreign_key "installs", "projects"
  add_foreign_key "installs", "versions"
  add_foreign_key "machine_grants", "machines"
  add_foreign_key "machine_grants", "projects"
  add_foreign_key "machines", "projects", column: "owner_id"
  add_foreign_key "project_machines", "machines"
  add_foreign_key "project_machines", "projects"
  add_foreign_key "sessions", "users"
  add_foreign_key "snapshots", "machines"
  add_foreign_key "versions", "apps"
end
