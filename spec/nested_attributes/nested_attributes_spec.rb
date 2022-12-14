require 'spec_helper'
require 'attr_json/nested_attributes'

RSpec.describe AttrJson::NestedAttributes do
  let(:model_class) do
    Class.new do
      include AttrJson::Model

      attr_json :str, :string
      attr_json :int, :integer
    end
  end

  let(:klass) do
    model_class_type = model_class.to_type
    Class.new(ActiveRecord::Base) do
      include AttrJson::Record
      include AttrJson::NestedAttributes

      self.table_name = "products"

      attr_json :one_model, model_class_type
      attr_json :many_models, model_class_type, array: true
      attr_json :array_of_strings, :string, array: true

      attr_json_accepts_nested_attributes_for :one_model, :many_models, :array_of_strings
    end
  end
  let(:instance) { klass.new }

  describe "on non-existing attributes" do
    it "should raise on non-existing associations" do
      expect {
        klass.attr_json_accepts_nested_attributes_for :nope
      }.to raise_error(ArgumentError, "No attr_json found for name 'nope'. Has it been defined yet?")
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

  describe "assigning via json_attributes" do
    it "allows assigning via raw hash object" do
      instance.json_attributes = {"one_model"=>{"str"=>"original"}}
      instance.save
      instance.reload
      expect(instance.one_model.str).to eq "original"
    end
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
        klass.attr_json_accepts_nested_attributes_for :one_model, reject_if: :all_blank
        example.run
        klass.attr_json_accepts_nested_attributes_for :one_model
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
        klass.attr_json_accepts_nested_attributes_for :many_models, reject_if: :all_blank
        example.run
        klass.attr_json_accepts_nested_attributes_for :many_models
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

  describe "array of primitives" do
    let(:setter) { :array_of_strings= }

    it "should_define_an_attribute_writer_method" do
      expect(instance).to respond_to setter
    end

    it "assign an array of strings on update" do
      instance.update({ array_of_strings_attributes: ["one", "two", "three"] })

      expect(instance.array_of_strings).to be_present
      expect(instance.array_of_strings).to eq(["one", "two", "three"])
    end

    it "removes nils and empty strings on update" do
      instance.update({ array_of_strings_attributes: ["", "one", nil, "two", "", "", "three"] })

      expect(instance.array_of_strings).to be_present
      expect(instance.array_of_strings).to eq(["one", "two", "three"])
    end

    it "assign an empty array" do
      instance.update({ array_of_strings_attributes: [] })

      expect(instance.array_of_strings).to eq([])
    end
  end

  describe "in an AttrJson::Model" do
    let(:klass) do
      model_class_type = model_class.to_type
      Class.new do
        include AttrJson::Model
        include AttrJson::NestedAttributes

        attr_json :one_model, model_class_type
        attr_json :many_models, model_class_type, array: true

        attr_json_accepts_nested_attributes_for :one_model, :many_models
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
        include AttrJson::Model

        attr_json :embedded_datetime, :datetime
        attr_json :embedded_date, :date
      end
    end

    let(:klass) do
      model_class_type = model_class.to_type
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record
        include AttrJson::NestedAttributes

        self.table_name = "products"

        attr_json :json_datetime, :datetime
        attr_json :json_date, :date

        attr_json :one_model, model_class_type
        attr_json :many_models, model_class_type, array: true

        attr_json_accepts_nested_attributes_for :one_model, :many_models
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

    # Date attributes have special problems, cause ActiveModel::Type::Date
    # doesn't work with multi-param attribute setting, I think because of a bug
    # nobody else cares about cause nobody else is using ActiveModel this way.
    # We make these tests pass by switching to ActiveRecord::Type.lookup instead
    # of ActiveModel::Type.lookup for symbol type args -- if tests still pass
    # either way, you could switch back if you want.
    describe(":date attribute") do
      it "assigns to direct attribute" do
        instance.assign_attributes(
          "json_date(1i)" => year_str,
          "json_date(2i)" => month_str,
          "json_date(3i)" => day_str
        )
        expect(instance.json_date).to be_kind_of(Date)
        expect(instance.json_date).to eq Date.new(year_str.to_i, month_str.to_i, day_str.to_i)
      end
    end
  end

  describe "defaults" do
    let(:klass) do
      model_class_type = model_class.to_type
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record
        include AttrJson::NestedAttributes

        attr_json_config(default_accepts_nested_attributes: { reject_if: :all_blank })

        self.table_name = "products"

        attr_json :one_model, model_class_type, accepts_nested_attributes: false
        attr_json :many_models, model_class_type, array: true
      end
    end

    it "applies default" do
      expect(instance).to respond_to(:many_models_attributes=)

      instance.many_models_attributes = [{}]
      expect(instance.many_models).to eq([])

      instance.many_models_attributes = [{str: "one"}]
      expect(instance.many_models.first.str).to eq("one")
    end

    it "overrides false" do
      expect(instance).not_to respond_to(:one_model_attributes=)
    end
  end
end
