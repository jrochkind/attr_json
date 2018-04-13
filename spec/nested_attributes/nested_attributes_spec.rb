require 'spec_helper'
require 'json_attribute/nested_attributes'

RSpec.describe JsonAttribute::NestedAttributes do
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

  describe "on non-existing attributes" do
    it "should raise on non-existing associations" do
      expect {
        klass.json_attribute_accepts_nested_attributes_for :nope
      }.to raise_error(ArgumentError, "No json_attribute found for name 'nope'. Has it been defined yet?")
    end
  end

  it "should allow class to override and call super" do
    overridden_class = Class.new(klass) do
      def one_model_attributes=(attrs)
        super(attrs.merge(str: "We Insist"))
      end
    end

    instance = overridden_class.new
    instance.one_model_attributes = { str: "James", int: 101 }
    expect(instance.one_model.str).to eq "We Insist"
    expect(instance.one_model.int).to eq 101
  end

  describe "single model attribute" do
    let(:setter) { :one_model_attributes= }

    it "should_define_an_attribute_writer_method" do
      expect(instance).to respond_to setter
    end

    it "assign a hash with string keys on update" do
      instance.update( { one_model_attributes: {str: "Someone", int: "101"}}.stringify_keys )
      expect(instance.one_model).to be_kind_of(model_class)
      expect(instance.one_model.str).to eq "Someone"
      expect(instance.one_model.int).to eq 101
    end

    describe "_destroy" do
      it "should accept args with _destroy='0'" do
       instance.update( { one_model_attributes: {str: "Someone", int: "", _destroy: "0"}}.stringify_keys )
       expect(instance.one_model).to be_kind_of(model_class)
       expect(instance.one_model.attributes).to eq({ "str" => "Someone", "int" => nil })
      end
    end



    describe "with existing record" do
      before do
        instance.one_model = {str: "original"}
        instance.save!
      end
      it "should delete object with _destroy" do
        instance.update(one_model_attributes: { str: "New", _destroy: "1"} )
        expect(instance.one_model).to be_nil
      end

      # not really sure if it should or not, maybe not
      skip "should re-use existing record" do
        original = instance.one_model

        instance.update(one_model_attributes: { str: "New"} )

        expect(instance.one_model).to equal(original)
        expect(instance.one_model.str).to eq "New"
      end
    end



    describe "reject_if" do
      around do |example|
        klass.json_attribute_accepts_nested_attributes_for :one_model, reject_if: :all_blank
        example.run
        klass.json_attribute_accepts_nested_attributes_for :one_model
      end


      it "should not build if all blank" do
        instance.update(( { one_model_attributes: {str: "", int: ""}}.stringify_keys ))
        instance.save!

        expect(instance.one_model).to be_nil
      end
      it "should build if not all blank" do
        instance.update({ one_model_attributes: {str: "str", int: ""}})
        instance.save!

        expect(instance.one_model).to be_kind_of(model_class)
        expect(instance.one_model.str).to eq "str"
        expect(instance.one_model.int).to be nil
      end
    end
  end


  describe "model array attribute" do
    let(:setter) { :many_models_attributes= }

    it "should_define_an_attribute_writer_method" do
      expect(instance).to respond_to setter
    end

    it "assign a hash with string keys on update" do
      instance.update( { many_models_attributes: [{str: "Someone", int: "101"}, {str: "Someone Else", int: "102"}]}.stringify_keys )

      expect(instance.many_models).to be_present
      expect(instance.many_models.all? {|a| a.kind_of? model_class})

      expect(instance.many_models).to eq [model_class.new(str: "Someone", int: "101"), model_class.new(str: "Someone Else", int: "102")]
    end

    describe "reject_if" do
      around do |example|
        klass.json_attribute_accepts_nested_attributes_for :many_models, reject_if: :all_blank
        example.run
        klass.json_attribute_accepts_nested_attributes_for :many_models
      end


      it "respect all_blank" do
        instance.update(
          {many_models_attributes: [{str: "", int: ""}, {str: "foo", int: ""}]}.stringify_keys
        )
        instance.save!

        expect(instance.many_models).to be_present
        expect(instance.many_models.all? {|a| a.kind_of? model_class})

        expect(instance.many_models).to eq [model_class.new(str: "foo", int: nil)]
      end
    end

    describe "_destroy" do
      it "should not add objects marked with _destroy" do
        # and should add despite _destroy: "0", without a _destroy attribute
        # being added.
        instance.update(
          many_models_attributes: [{ str: "nope", _destroy: "1" }, { str: "yep", _destroy: "0" }]
        )
        expect(instance.many_models).to eq [model_class.new(str: "yep")]
      end
    end
  end

  describe "in an JsonAttribute::Model" do
    let(:klass) do
      model_class_type = model_class.to_type
      Class.new do
        include JsonAttribute::Model
        include JsonAttribute::NestedAttributes

        json_attribute :one_model, model_class_type
        json_attribute :many_models, model_class_type, array: true

        json_attribute_accepts_nested_attributes_for :one_model, :many_models
      end
    end

    it "should define methods" do
      expect(instance).to respond_to :one_model_attributes=
      expect(instance).to respond_to :many_models_attributes=
      expect(instance).to respond_to :build_one_model
      expect(instance).to respond_to :build_many_model
    end

    it "assign for single model" do
      instance.one_model_attributes= {str: "Someone", int: "101"}.stringify_keys
      expect(instance.one_model).to be_kind_of(model_class)
      expect(instance.one_model.str).to eq "Someone"
      expect(instance.one_model.int).to eq 101
    end

    it "assigns for array of models" do
      instance.many_models_attributes =
        [
          {str: "Someone", int: "101"},
          {str: "Someone Else", int: "102"}
        ].collect(&:stringify_keys)

      expect(instance.many_models).to be_present
      expect(instance.many_models.all? {|a| a.kind_of? model_class})

      expect(instance.many_models).to eq [model_class.new(str: "Someone", int: "101"), model_class.new(str: "Someone Else", int: "102")]
    end
  end

  describe "multiparameter attributes" do
    let(:model_class) do
      Class.new do
        include JsonAttribute::Model

        json_attribute :embedded_datetime, :datetime
      end
    end

    let(:klass) do
      model_class_type = model_class.to_type
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record
        include JsonAttribute::NestedAttributes

        self.table_name = "products"

        json_attribute :json_datetime, :datetime

        json_attribute :one_model, model_class_type
        json_attribute :many_models, model_class_type, array: true

        json_attribute_accepts_nested_attributes_for :one_model, :many_models
      end
    end
    let(:instance) { klass.new }

    let(:year_str) { "2018" }
    let(:month_str) { "4" }
    let(:day_str) { "13" }

    it "assigns to direct attribute" do
      instance.assign_attributes(
        "json_datetime(1i)" => year_str,
        "json_datetime(2i)" => month_str,
        "json_datetime(3i)" => day_str
      )
      expect(instance.json_datetime).to be_kind_of(Time)
      expect(instance.json_datetime).to eq Time.utc(year_str.to_i, month_str.to_i, day_str.to_i)
    end

    it "assigns to single model attribute" do
      instance.assign_attributes(
        "one_model_attributes" => {
          "embedded_datetime(1i)" => year_str,
          "embedded_datetime(2i)" => month_str,
          "embedded_datetime(3i)" => day_str
        }
      )
      expect(instance.one_model.embedded_datetime).to be_kind_of(Time)
      expect(instance.one_model.embedded_datetime).to eq Time.utc(year_str.to_i, month_str.to_i, day_str.to_i)
    end

    it "assigns to array of models attribute" do
      instance.assign_attributes(
        "many_models_attributes" => [
          {
            "embedded_datetime(1i)" => year_str,
            "embedded_datetime(2i)" => month_str,
            "embedded_datetime(3i)" => day_str
          },
          {
            "embedded_datetime(1i)" => year_str,
            "embedded_datetime(2i)" => month_str,
            "embedded_datetime(3i)" => day_str
          }
        ]
      )

      expect(instance.many_models.count).to eq 2
      expect(
        instance.many_models.to_a.all? { |m| m.kind_of? model_class }
      ).to be true
      expect(
        instance.many_models.all? { |m| m.embedded_datetime.kind_of? Time }
      ).to be true
      expect(
        instance.many_models.all? { |m| m.embedded_datetime == Time.utc(year_str.to_i, month_str.to_i, day_str.to_i) }
      ).to be true
    end

  end

end
