require 'spec_helper'

RSpec.describe "subclassing" do
  let!(:parent_class) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "products"

      include AttrJson::Record
      attr_json_config(default_container_attribute: "other_attributes")

      attr_json :parent_str, :string
      attr_json :parent_int, :integer
    end
  end

  let!(:sub_class) do
    Class.new(parent_class) do
      attr_json :child_str, :string
    end
  end

  describe "parent class" do
    let(:registry_definitions) { parent_class.attr_json_registry.definitions }


    it "has only it's own attr_jsons" do
      expect(registry_definitions.collect(&:name)).to eq [:parent_str, :parent_int]
    end
  end

  describe "subclass" do
    let(:registry_definitions) { sub_class.attr_json_registry.definitions }

    it "has inherited attr_json's and it's own" do
      expect(registry_definitions.collect(&:name)).to eq [:parent_str, :parent_int, :child_str]
    end

    it "inherits attr_json_config" do
      expect(sub_class.attr_json_config.default_container_attribute).to eq "other_attributes"
    end

    describe "override config" do
      let!(:sub_class) do
        Class.new(parent_class) do
          attr_json_config(default_container_attribute: "json_attributes")

          attr_json :child_str, :string
        end
      end

      it "subclass has overridden" do
        expect(sub_class.attr_json_config.default_container_attribute).to eq "json_attributes"
      end
      it "parent class has original" do
        expect(parent_class.attr_json_config.default_container_attribute).to eq "other_attributes"
      end
    end

  end

end
