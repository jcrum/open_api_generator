# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the canonical source for the database schema. If you need to
# create the database, run `bin/rails db:schema:load`.

ActiveRecord::Schema[8.1].define(version: 2026_08_14_000000) do
  create_table "gadgets", force: :cascade do |t|
    t.string "title", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
