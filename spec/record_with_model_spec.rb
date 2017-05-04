# We make a seperate spec file for a record holding a model, just
# cause it's special enough and the existing file is long enough.
#
# Our specs need to be seriously DRY'd up, prob with rspec shared examples,
# both within files, and between model/record.
require 'json_attribute/model'
RSpec.describe JsonAttribute::Record do
  let(:datetime_value) { DateTime.now }
  let(:model_class) do
    Class.new do
      include JsonAttribute::Model

      json_attribute :str, :string
      json_attribute :int, :integer
      json_attribute :int_array, :integer, array: true
      json_attribute :int_with_default, :integer, default: 5
      json_attribute :datetime, :datetime
    end
  end
  let(:klass) do
    # really hard to get the class def closure to capture the rspec
    # `let` for some reason, but this works.
    model_class_type = model_class.to_type
    Class.new(ActiveRecord::Base) do
      include JsonAttribute::Record
      self.table_name = "products"

      json_attribute :model, model_class_type
    end
  end
  let(:instance) { klass.new }

# TODO datetimes are weird, sometimes rails takes off fractional seconds, sometimes it doesn't.

  it "can set, save, and load with real object" do
    instance.model = model_class.new(str: 'string value', int: "12", int_array: "12")

    expect(instance.model).to be_kind_of(model_class)
    expect(instance.model.str).to eq("string value")
    expect(instance.model.int).to eq(12)
    expect(instance.model.int_array).to eq([12])
    expect(instance.model.int_with_default).to eq(5)
    expect(instance.json_attributes).to eq(
      'model' => model_class.new(
        "str"=>"string value",
        "int"=>12,
        "int_array"=>[12],
        "int_with_default"=> 5
      )
    )
    # Before save, we can still use to_json
    expect(JSON.parse(instance.to_json)["json_attributes"]).to eq(
      "model" => {
        "str"=>"string value",
        "int"=>12,
        "int_array"=>[12],
        "int_with_default"=> 5
      }
    )

    instance.save!
    instance.reload

    expect(instance.model).to be_kind_of(model_class)
    expect(instance.model.str).to eq("string value")
    expect(instance.model.int).to eq(12)
    expect(instance.model.int_array).to eq([12])
    expect(instance.model.int_with_default).to eq(5)
    expect(instance.json_attributes).to eq(
      'model' => model_class.new("str"=>"string value", "int"=>12, "int_array"=>[12], "int_with_default"=> 5)
    )

    expect(JSON.parse(instance.json_attributes_before_type_cast)).to eq(
      "model" => {
        "str"=>"string value", "int"=>12, "int_array"=>[12], "int_with_default"=> 5
      }
    )
  end

  it "can set, save, and load with hash" do
    instance.model = {str: 'string value', int: "12", int_array: "12"}

    expect(instance.model).to be_kind_of(model_class)
    expect(instance.model.str).to eq("string value")
    expect(instance.model.int).to eq(12)
    expect(instance.model.int_array).to eq([12])
    expect(instance.model.int_with_default).to eq(5)
    expect(instance.json_attributes).to eq(
      'model' => model_class.new(
        "str"=>"string value",
        "int"=>12,
        "int_array"=>[12],
        "int_with_default"=> 5
      )
    )
    # Before save, we can still use to_json
    expect(JSON.parse(instance.to_json)["json_attributes"]).to eq(
      "model" => {
        "str"=>"string value",
        "int"=>12,
        "int_array"=>[12],
        "int_with_default"=> 5
      }
    )

    instance.save!
    instance.reload

    expect(instance.model).to be_kind_of(model_class)
    expect(instance.model.str).to eq("string value")
    expect(instance.model.int).to eq(12)
    expect(instance.model.int_array).to eq([12])
    expect(instance.model.int_with_default).to eq(5)
    expect(instance.json_attributes).to eq(
      'model' => model_class.new("str"=>"string value", "int"=>12, "int_array"=>[12], "int_with_default"=> 5)
    )
    # TODO after save we can use json_attributes_before_type_cast
    # Only way to see what it REALLY serializes as is with #to_json, oh well.
    expect(JSON.parse(instance.to_json)["json_attributes"]).to eq(
      "model" => {
        "str"=>"string value", "int"=>12, "int_array"=>[12], "int_with_default"=> 5
      }
    )
  end

  describe "explicitly set to nil" do
    it "is nil" do
      instance.model = nil
      expect(instance.json_attributes).to eq("model" => nil)
      expect(JSON.parse(instance.to_json)["json_attributes"]).to eq("model" => nil)
      instance.save!

      expect(instance.json_attributes_before_type_cast).to eq "{\"model\":null}"
    end
  end

  describe "with weird input" do
    it "ignores input" do
      # this SEEMS to be consistent with what other ActiveModel::Types do...
      instance.model = "this is not a model"
      expect(instance.model).to be nil

      # i'd be fine if it set key to nil, but current implementation
      # seems to not set key at all, which is also fine.
      expect(instance.json_attributes).to eq({})

      instance.save!

      expect(instance.json_attributes_before_type_cast).to eq("{}")
    end
  end

  # TODO test deeply nested models? Pretty sure we're fine.

  describe "array of models" do
    let(:klass) do
      # really hard to get the class def closure to capture the rspec
      # `let` for some reason, but this works.
      model_class_type = model_class.to_type
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record
        self.table_name = "products"

        json_attribute :models, model_class_type, array: true
      end
    end

    describe "set single model" do
      before do
        instance.models = model_class.new(str: 'string value', int: "12", int_array: "12")
      end
      it "casts single model to array" do
        expect(instance.models).to be_kind_of(Array)
        expect(instance.models).to eq([model_class.new(str: 'string value', int: "12", int_array: "12")])
        expect(instance.json_attributes).to eq(
          "models" => [model_class.new(str: 'string value', int: "12", int_array: "12")]
        )
        instance.save!
        instance.reload
        expect(instance.models).to be_kind_of(Array)
        expect(instance.models).to eq([model_class.new(str: 'string value', int: "12", int_array: "12")])
        expect(instance.json_attributes).to eq(
          "models" => [model_class.new(str: 'string value', int: "12", int_array: "12")]
        )
      end
    end

    describe "array of hash parameters" do
      before do
        instance.models = [
          {str: 'string value', int: 12},
          {str: 'string value', int: 12},
        ]
      end
      it "casts all the way, with defaults" do
        expect(instance.models).to eq([
          model_class.new(str: 'string value', int: "12"),
          model_class.new(str: 'string value', int: "12")
        ])

        instance.save!
        serialized = JSON.parse(instance.json_attributes_before_type_cast)

        expect(serialized["models"]).to eq([
          {"str"=>"string value", "int"=>12, "int_with_default"=>5},
          {"str"=>"string value", "int"=>12, "int_with_default"=>5}
        ])
      end
    end

    describe "single hash param" do
      before do
        instance.models = {str: 'string value', int: 12}
      end
      it "casts all the way, with defaults" do
        expect(instance.models).to eq([
          model_class.new(str: 'string value', int: "12")
        ])

        instance.save!
        serialized = JSON.parse(instance.json_attributes_before_type_cast)

        expect(serialized["models"]).to eq([
          {"str"=>"string value", "int"=>12, "int_with_default"=>5}
        ])
      end
    end

    describe "with existing array" do
      before do
        instance.models = [model_class.new(str: 'string value', int: "12", int_array: "12")]
        instance.save!
      end
      it "lets us add on and save" do
        instance.models << model_class.new(str: 'new value', int: "100", int_array: "100")
        expect(instance.changed?).to be true
        instance.save!
        instance.reload

        expect(instance.models.length).to be 2
        serialized = JSON.parse(instance.json_attributes_before_type_cast)
        expect(serialized["models"]).to be_kind_of(Array)
        expect(serialized["models"].length).to be 2
        expect(serialized["models"]).to eq([
          {"int"=>12, "str"=>"string value", "int_array"=>[12], "int_with_default"=>5},
          {"int"=>100, "str"=>"new value", "int_array"=>[100], "int_with_default"=>5}
        ])
      end
    end

  end
#TODO default {} should give you a blank model please, or lambda with constructor should also work.
# TODO even if model has defaults, if you don't set the model to anything, model key
#   shoudl be nil!
end
