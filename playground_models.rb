# required by our bin/console, nothing but something to play with.

require 'attr_json'
class TestModel
  include AttrJson::Model

  attr_json :str, :string
  attr_json :int, :integer
end

class LangAndValue
  include AttrJson::Model

  attr_json :lang, :string, default: "en"
  attr_json :value, :string

  # Yes, you can use ordinary validations... I think. If not, soon.
end

class SomeLabels
  include AttrJson::Model

  attr_json :hello, LangAndValue.to_type, array: true
  attr_json :goodbye, LangAndValue.to_type, array: true
end


class MyModel2 < ActiveRecord::Base
  self.table_name = "products"
   include AttrJson::Record
   include AttrJson::Record::QueryScopes

   # use any ActiveModel::Type types: string, integer, decimal (BigDecimal),
   # float, datetime, boolean.
   attr_json :my_string, :string
   attr_json :my_integer, :integer
   attr_json :my_datetime, :datetime

   # You can have an _array_ of those things too.
   attr_json :int_array, :integer, array: true

   #and/or defaults
   #attr_json :int_with_default, :integer, default: 100

  attr_json :special_string, :string, store_key: "__my_string"

  attr_json :lang_and_value, LangAndValue.to_type
  # YES, you can even have an array of them
  attr_json :lang_and_value_array, LangAndValue.to_type, array: true

  attr_json :my_labels, SomeLabels.to_type
end

class MyEmbeddedModel
  include AttrJson::Model

  attr_json :str, :string
end

class MyModel < ActiveRecord::Base
  self.table_name = "products"

  include AttrJson::Record
  include AttrJson::Record::Dirty

  attr_json :str, :string
  attr_json :str_array, :string, array: true
  attr_json :array_of_models, MyEmbeddedModel.to_type, array: true
end

class StaticProduct < ActiveRecord::Base
  self.table_name = "products"
  belongs_to :product_category
end

class Product < StaticProduct
  include AttrJson::Record
  include AttrJson::Record::QueryScopes
  include AttrJson::Record::Dirty

  attr_json :title, :string
  attr_json :rank, :integer
  attr_json :made_at, :datetime
  attr_json :time, :time
  attr_json :date, :date
  attr_json :dec, :decimal
  attr_json :int_array, :integer, array: true
  attr_json :model, TestModel.to_type

  #jsonb_accessor :options, title: :string, rank: :integer, made_at: :datetime
end




class ProductCategory < ActiveRecord::Base
  include AttrJson::Record

  #jsonb_accessor :options, title: :string
  has_many :products
end
