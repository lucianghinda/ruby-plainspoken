ActiveRecord::Schema[8.0].define(version: 2026_08_20_120000) do
  enable_extension "plpgsql"

  create_table "venues", force: :cascade do |t|
    t.string "name", null: false
    t.string "time_zone", null: false, default: "Europe/London"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "shifts", force: :cascade do |t|
    t.bigint "venue_id", null: false
    t.datetime "starts_at", null: false
    t.datetime "ends_at", null: false
    t.string "state", null: false, default: "draft"
    t.integer "pay_rate_pence", null: false
    t.datetime "published_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["venue_id", "starts_at"], name: "index_shifts_on_venue_id_and_starts_at"
  end

  create_table "bookings", force: :cascade do |t|
    t.bigint "shift_id", null: false
    t.bigint "worker_id", null: false
    t.string "state", null: false, default: "pending"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["shift_id", "worker_id"], name: "index_bookings_on_shift_id_and_worker_id", unique: true
  end

  create_table "workers", force: :cascade do |t|
    t.string "name", null: false
    t.string "email", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_workers_on_email", unique: true
  end

  add_foreign_key "bookings", "shifts"
  add_foreign_key "bookings", "workers"
  add_foreign_key "shifts", "venues"
end
