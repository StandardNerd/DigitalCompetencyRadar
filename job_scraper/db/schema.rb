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

ActiveRecord::Schema[8.0].define(version: 2025_03_20_005425) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "job_listings", force: :cascade do |t|
    t.string "job_id"
    t.string "portal"
    t.string "title"
    t.string "organization"
    t.text "content"
    t.string "url"
    t.boolean "processed"
    t.bigint "scraper_job_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scraper_job_id"], name: "index_job_listings_on_scraper_job_id"
  end

  create_table "scraper_configurations", force: :cascade do |t|
    t.string "name"
    t.string "portal_type"
    t.string "default_keyword"
    t.integer "default_results"
    t.integer "collect_count"
    t.integer "checkpoint_interval"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "scraper_jobs", force: :cascade do |t|
    t.string "name"
    t.string "portal"
    t.string "keyword"
    t.integer "results"
    t.string "mode"
    t.integer "collect_count"
    t.integer "checkpoint_interval"
    t.string "status"
    t.text "message"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.bigint "user_id", null: false
    t.bigint "scraper_configuration_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["scraper_configuration_id"], name: "index_scraper_jobs_on_scraper_configuration_id"
    t.index ["user_id"], name: "index_scraper_jobs_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "job_listings", "scraper_jobs"
  add_foreign_key "scraper_jobs", "scraper_configurations"
  add_foreign_key "scraper_jobs", "users"
end
