class Document < ActiveRecord::Base
  include JsonAttribute::Record
  include JsonAttribute::NestedAttributes

  json_attribute :title, :string

  json_attribute :person_roles, PersonRole.to_type, array: true
  json_attribute_accepts_nested_attributes_for :person_roles
end
