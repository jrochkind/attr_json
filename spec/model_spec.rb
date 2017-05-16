require 'spec_helper'

RSpec.describe JsonAttribute::Record do
  let(:instance) { klass.new }

  describe "store_key" do
    let(:klass) do
      Class.new do
        include JsonAttribute::Model

        json_attribute :str_one, :string, store_key: "__str_one"
      end
    end

    it "reads attribute name from initializer" do
      instance = klass.new(str_one: "value")
      expect(instance.str_one).to eq("value")
      # attribute name in attributes
      expect(instance.attributes).to eq("str_one" => "value")
      # but store_key when serialized
      expect(instance.as_json).to eq("__str_one" => "value")
    end

    it "reads attribute name from assign_attributes" do
      instance.assign_attributes(str_one: "value")
      expect(instance.str_one).to eq("value")
      # attribute name in attributes
      expect(instance.attributes).to eq("str_one" => "value")
      # but store_key when serialized
      expect(instance.as_json).to eq("__str_one" => "value")
    end
  end

  describe "validation" do
    let(:klass) do
      Class.new do
        include JsonAttribute::Model

        # validations need a model_name, which our anon class doens't have
        def self.model_name
          ActiveModel::Name.new(self, nil, "TestClass")
        end

        validates :str_array, presence: true
        validates :str,
          inclusion: {
            in: %w(small medium large),
            message: "%{value} is not a valid size"
          }

        json_attribute :str, :string
        json_attribute :str_array, :string, array: true
      end
    end

    it "has the usual validation errors" do
      instance.str = "nosize"
      expect(instance.valid?).to be false
      expect(instance.errors[:str_array]).to eq(["can't be blank"])
      expect(instance.errors[:str]).to eq(["nosize is not a valid size"])
    end
    it "valid with valid data" do
      instance.str = "small"
      instance.str_array = ["foo"]
      expect(instance.valid?).to be true
    end
  end

  describe "nested model with validation" do
    let(:nested_class) do
      Class.new do
        include JsonAttribute::Model
        def self.model_name ; ActiveModel::Name.new(self, nil, "NestedClass") ; end
        json_attribute :str, :string
        validates_presence_of :str
      end
    end
    let(:klass) do
      nested_class_type = nested_class.to_type
      Class.new do
        include JsonAttribute::Model
        def self.model_name ; ActiveModel::Name.new(self, nil, "Klass") ; end

        json_attribute :nested, nested_class_type, default: {}
      end
    end

    it "is invalid when nested is" do
      expect(instance.valid?).to be false
      expect(instance.errors.key?(:nested)).to be true
      expect(instance.errors[:nested]).to include("is invalid")

      expect(instance.nested.errors.key?(:str))
      expect(instance.nested.errors[:str]).to include("can't be blank")

      expect(instance.errors.details[:nested].first[:value]).to be_kind_of(nested_class)
    end

    it "is valid when nested is" do
      instance.nested.str = "something"
      expect(instance.valid?).to be true
    end
  end

  describe "nested array of models with validation" do
    let(:nested_class) do
      Class.new do
        include JsonAttribute::Model
        def self.model_name ; ActiveModel::Name.new(self, nil, "NestedClass") ; end
        json_attribute :str, :string
        validates_presence_of :str
      end
    end
    let(:klass) do
      nested_class_type = nested_class.to_type
      Class.new do
        include JsonAttribute::Model
        def self.model_name ; ActiveModel::Name.new(self, nil, "Klass") ; end

        json_attribute :nested, nested_class_type, array: true, default: [{}]
      end
    end

    it "is invalid when nested is" do
      expect(instance.valid?).to be false
      expect(instance.errors.key?(:nested)).to be true
      expect(instance.errors[:nested]).to include("is invalid")

      expect(instance.nested.first.errors.key?(:str))
      expect(instance.nested.first.errors[:str]).to include("can't be blank")

      expect(instance.errors.details[:nested].first[:value].first).to be_kind_of(nested_class)
    end

    it "is valid when nested is" do
      instance.nested.first.str = "something"
      expect(instance.valid?).to be true
    end
  end


end
