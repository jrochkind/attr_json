class Document < ActiveRecord::Base
  include AttrJson::Record

  attr_json :title, :string

  attr_json :person_roles, PersonRole.to_type, array: true
  attr_json_accepts_nested_attributes_for :person_roles
end
