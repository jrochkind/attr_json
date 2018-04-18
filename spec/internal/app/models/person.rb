class Person
  include JsonAttribute::Model
  include JsonAttribute::Model::CocoonCompat

  json_attribute :given_name, :string
  json_attribute :family_name, :string
  json_attribute :birth_date, :datetime

  validates_presence_of :given_name
end
