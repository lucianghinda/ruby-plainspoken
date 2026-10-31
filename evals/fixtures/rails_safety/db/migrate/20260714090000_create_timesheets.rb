class CreateTimesheets < ActiveRecord::Migration[8.0]
  def change
    create_table :timesheets do |t|
      t.references :worker, null: false, foreign_key: true
      t.references :venue, null: false, foreign_key: true
      t.date :week_starting, null: false
      t.decimal :hours, precision: 6, scale: 2, null: false
      t.string :state, null: false, default: "submitted"
      t.references :approved_by, null: true, foreign_key: { to_table: :users }
      t.datetime :approved_at

      t.timestamps
    end

    add_index :timesheets,
              [:worker_id, :venue_id, :week_starting],
              unique: true,
              name: "index_timesheets_on_worker_venue_week"
  end
end
