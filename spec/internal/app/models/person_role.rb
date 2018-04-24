class PersonRole
  include AttrJson::Model
  include AttrJson::NestedAttributes
  include AttrJson::Model::CocoonCompat

  attr_json :role, :string
  attr_json :people, Person.to_type, array: true

  attr_json_accepts_nested_attributes_for :people
end
