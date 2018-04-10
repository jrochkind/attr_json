require 'spec_helper'
require 'json_attribute/nested_attributes'

RSpec.describe "NestedAttributes build methods" do
  let(:model_class) do
    Class.new do
      include JsonAttribute::Model

      json_attribute :str, :string
      json_attribute :int, :integer
    end
  end

  let(:klass) do
    model_class_type = model_class.to_type
    Class.new(ActiveRecord::Base) do
      include JsonAttribute::Record
      include JsonAttribute::NestedAttributes

      self.table_name = "products"

      json_attribute :one_model, model_class_type
      json_attribute :many_models, model_class_type, array: true

      json_attribute_accepts_nested_attributes_for :one_model, :many_models
    end
  end
  let(:instance) { klass.new }

  describe "single model attr" do
    it "has build method" do
      expect(instance).to respond_to("build_one_model")
    end
    it "builds" do
      expect(instance.build_one_model).to be_kind_of model_class
      expect(instance.one_model).to be_kind_of model_class
    end
    it "builds with params" do
      expect(instance.build_one_model(str: "foo", int: "")).to eq model_class.new(str: "foo", int: nil)
      expect(instance.one_model).to eq model_class.new(str: "foo", int: nil)
    end
    it "replaces existing object" do
      # AR seems to do this on to-ones, so we will too.
      instance.one_model = {}
      original = instance.one_model
      expect(original).to be_kind_of model_class

      new_one = instance.build_one_model(str: "foo")
      expect(new_one).not_to equal original
    end
  end

  describe "array of model attr" do
    it "has build method using singularized name" do
      expect(instance).to respond_to("build_many_model")
    end

    it "builds" do
      built = instance.build_many_model
      expect(built).to be_kind_of model_class
      expect(built).to equal instance.many_models.last
    end

    it "builds with params" do
      built = instance.build_many_model(str: "foo", int: "")

      expect(instance.many_models).to eq [model_class.new(str: "foo", int: nil)]
      expect(built).to equal instance.many_models.last
    end

    it "adds on to end of existing array" do
      instance.many_models = [{str: "original"}]

      built = instance.build_many_model(str: "foo", int: "")
      expect(built).to equal instance.many_models.last

      expect(instance.many_models).to eq [model_class.new(str: "original"), model_class.new(str: "foo", int: nil)]
    end
  end

  describe "with define_build_method: false" do
    let(:klass) do
      model_class_type = model_class.to_type
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record
        include JsonAttribute::NestedAttributes

        self.table_name = "products"

        json_attribute :one_model, model_class_type
        json_attribute :many_models, model_class_type, array: true

        json_attribute_accepts_nested_attributes_for :one_model, :many_models, define_build_method: false
      end
    end

    it "does not add build methods" do
      expect(instance).not_to respond_to(:build_many_model)
      expect(instance).not_to respond_to(:build_one_model)
    end
  end
end
