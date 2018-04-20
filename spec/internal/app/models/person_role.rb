class PersonRole
  include JsonAttribute::Model
  include JsonAttribute::NestedAttributes
  include JsonAttribute::Model::CocoonCompat

  json_attribute :role, :string
  json_attribute :people, Person.to_type, array: true

  json_attribute_accepts_nested_attributes_for :people
end
