ActiveRecord::Schema.define do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "product_categories", force: :cascade do |t|
    t.jsonb "options"
  end

  create_table "products", force: :cascade do |t|
    t.jsonb    "json_attributes"
    t.jsonb    "other_attributes"
    t.string   "string_type"
    t.integer  "integer_type"
    t.integer  "product_category_id"
    t.boolean  "boolean_type"
    t.float    "float_type"
    t.time     "time_type"
    t.date     "date_type"
    t.datetime "datetime_type"
    t.decimal  "decimal_type"
  end

  create_table "documents", force: :cascade do |t|
    t.jsonb    "json_attributes"
  end

  create_table "st_inherit_widgets" do |t|
    t.jsonb "json_attributes"
    t.string "title"
    t.string "type"
  end
end
