ActiveRecord::Schema[8.0].define(version: 2026_07_14_090000) do
  enable_extension "plpgsql"

  create_table "timesheets", force: :cascade do |t|
    t.bigint "worker_id", null: false
    t.bigint "venue_id", null: false
    t.date "week_starting", null: false
    t.decimal "hours", precision: 6, scale: 2, null: false
    t.string "state", null: false, default: "submitted"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["worker_id", "venue_id", "week_starting"], name: "index_timesheets_on_worker_venue_week", unique: true
  end

  add_foreign_key "timesheets", "users", column: "approved_by_id"
  add_foreign_key "timesheets", "venues"
  add_foreign_key "timesheets", "workers"
end
