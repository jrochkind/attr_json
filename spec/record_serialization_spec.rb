require 'attr_json/model'
RSpec.describe "AttrJson::Record serialization" do

  class Product
    include AttrJson::Model
    attr_json :name, :string, default: "A Product"
    attr_json :cost, :string, default: "$2.25"
    attr_json :material, :string, default: "silk"
    attr_json :color, :string, default: "green"
  end

  class Brand
    include AttrJson::Model

    def self.build_test
      new(products: [Product.new] )
    end

    attr_json :name, :string, default: "Some Brand"
    attr_json :products, Product.to_type, array: true, default: []
  end

  class Department
    include AttrJson::Model

    def self.build_test
      new(brands: [Brand.build_test]  )
    end

    attr_json :name, :string, default: "Some Department"
    attr_json :brands, Brand.to_type, array: true, default: []
  end


  class Store < ActiveRecord::Base
    include AttrJson::Record

    self.table_name = "products"

    attr_json :departments, Department.to_type, container_attribute: :other_attributes, array: true, default: []
  end


  let(:unsaved_store) { Store.new(departments: Array.new(3) { Department.build_test }) }

  describe "#as_json" do

    # This seems to pass, everything is properly json-ified
    it "produces json-value-only-hash" do
      expect(only_json_values?( unsaved_store.as_json )).to be true
    end
  end

  describe "#serializable_hash" do

    # This does not pass, values are still ruby objects
    it "produces json-value-only-hash" do
      expect(only_json_values?( unsaved_store.serializable_hash )).to be true
    end
  end

  def only_json_values?(value)
    case value
    when Hash
      value.keys.all? {|v| v.kind_of?(String) } && value.values.all? { |v| only_json_values?(v) }
    when Array
      value.all? { |v| only_json_values?(v) }
    else
      value.is_a?(String) || value.is_a?(Numeric) || value == true || value == false || value.nil?
    end
  end

end
