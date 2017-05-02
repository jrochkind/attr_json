# required by our bin/console, nothing but something to play with.

require 'json_attribute'
class TestModel
  include JsonAttribute::Model

  json_attribute :str, :string
  json_attribute :int, :integer
end

class StaticProduct < ActiveRecord::Base
  self.table_name = "products"
  belongs_to :product_category
end

class Product < StaticProduct
  include JsonAttribute::Record

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
