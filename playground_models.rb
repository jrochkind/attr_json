# required by our bin/console, nothing but something to play with.

require 'json_attribute'
class TestModel
  include JsonAttribute::Model

  json_attribute :str, :string
  json_attribute :int, :integer
end

class LangAndValue
  include JsonAttribute::Model

  json_attribute :lang, :string, default: "en"
  json_attribute :value, :string

  # Yes, you can use ordinary validations... I think. If not, soon.
end

class SomeLabels
  include JsonAttribute::Model

  json_attribute :hello, LangAndValue.to_type, array: true
  json_attribute :goodbye, LangAndValue.to_type, array: true
end


class MyModel < ActiveRecord::Base
  self.table_name = "products"
   include JsonAttribute::Record
   include JsonAttribute::Record::QueryScopes

   # use any ActiveModel::Type types: string, integer, decimal (BigDecimal),
   # float, datetime, boolean.
   json_attribute :my_string, :string
   json_attribute :my_integer, :integer
   json_attribute :my_datetime, :datetime

   # You can have an _array_ of those things too.
   json_attribute :int_array, :integer, array: true

   #and/or defaults
   #json_attribute :int_with_default, :integer, default: 100

  json_attribute :special_string, :string, store_key: "__my_string"

  json_attribute :lang_and_value, LangAndValue.to_type
  # YES, you can even have an array of them
  json_attribute :lang_and_value_array, LangAndValue.to_type, array: true

  json_attribute :my_labels, SomeLabels.to_type
end

class StaticProduct < ActiveRecord::Base
  self.table_name = "products"
  belongs_to :product_category
end

class Product < StaticProduct
  include JsonAttribute::Record
  include JsonAttribute::Record::QueryScopes
  include JsonAttribute::Record::Dirty

  json_attribute :title, :string
  json_attribute :rank, :integer
  json_attribute :made_at, :datetime
  json_attribute :time, :time
  json_attribute :date, :date
  json_attribute :dec, :decimal
  json_attribute :int_array, :integer, array: true
  json_attribute :model, TestModel.to_type

  #jsonb_accessor :options, title: :string, rank: :integer, made_at: :datetime
end




class ProductCategory < ActiveRecord::Base
  include JsonAttribute::Record

  #jsonb_accessor :options, title: :string
  has_many :products
end
