class Person
  include AttrJson::Model
  include AttrJson::Model::CocoonCompat

  attr_json :given_name, :string
  attr_json :family_name, :string
  attr_json :birth_date, :date

  validates_presence_of :given_name
end
