require 'spec_helper'

RSpec.describe JsonAttribute::Record do
  let(:klass) do
    Class.new(ActiveRecord::Base) do
      include JsonAttribute::Record

      self.table_name = "products"
      json_attribute :str, :string
      json_attribute :int, :integer
      json_attribute :int_array, :integer, array: true
      json_attribute :int_with_default, :integer, default: 5
    end
  end
  let(:instance) { klass.new }

  [
    [:integer, 12, "12"],
    [:string, "12", 12],
    [:decimal, BigDecimal.new("10.01"), "10.0100"],
    [:boolean, true, "t"],
    [:date, Date.parse("2017-04-28"), "2017-04-28"],
    [:datetime, DateTime.parse("2017-04-04 04:45:00").to_time, "2017-04-04T04:45:00Z"],
    [:float, 45.45, "45.45"]
  ].each do |type, cast_value, uncast_value|
    describe "for primitive type #{type}" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record

          self.table_name = "products"
          json_attribute :value, type
        end
      end
      it "properly saves good #{type}" do
        instance.value = cast_value
        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)

        instance.save!
        instance.reload

        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)
      end
      it "casts to #{type}" do
        instance.value = uncast_value
        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)

        instance.save!
        instance.reload

        expect(instance.value).to eq(cast_value)
        expect(instance.json_attributes["value"]).to eq(cast_value)
      end
    end
  end

  it "supports arrays" do
    instance.int_array = %w(1 2 3)
    expect(instance.int_array).to eq([1, 2, 3])
    instance.save!
    instance.reload
    expect(instance.int_array).to eq([1, 2, 3])

    instance.int_array = 1
    expect(instance.int_array).to eq([1])
    instance.save!
    instance.reload
    expect(instance.int_array).to eq([1])
  end

  # TODO: Should it LET you redefine instead, and spec for that? Have to pay
  # attention to store keys too if we let people replace attributes.
  it "raises on re-using attribute name" do
    expect {
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record

        self.table_name = "products"
        json_attribute :value, :string
        json_attribute :value, :integer
      end
    }.to raise_error(ArgumentError, /Can't add, conflict with existing attribute name `value`/)
  end

  context "defaults" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record

        self.table_name = "products"
        json_attribute :str_with_default, :string, default: "DEFAULT_VALUE"
      end
    end

    it "supports defaults" do
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
    end

    it "saves default even without access" do
      instance.save!
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to include("str_with_default" => "DEFAULT_VALUE")
      instance.reload
      expect(instance.str_with_default).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to include("str_with_default" => "DEFAULT_VALUE")
    end

    it "lets default override with nil" do
      instance.str_with_default = nil
      expect(instance.str_with_default).to eq(nil)
      instance.save
      instance.reload
      expect(instance.str_with_default).to eq(nil)
      expect(instance.json_attributes).to include("str_with_default" => nil)
    end
  end

  context "store keys" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        self.table_name = "products"
        include JsonAttribute::Record
        json_attribute :value, :string, default: "DEFAULT_VALUE", store_key: :_store_key
      end
    end

    it "puts the default value in the jsonb hash at the given store key" do
      expect(instance.value).to eq("DEFAULT_VALUE")
      expect(instance.json_attributes).to eq("_store_key" => "DEFAULT_VALUE")
    end

    it "sets the value at the given store key" do
      instance.value = "set value"
      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")

      instance.save!
      instance.reload

      expect(instance.value).to eq("set value")
      expect(instance.json_attributes).to eq("_store_key" => "set value")
    end

    context "inheritance" do
      let(:subklass) do
        Class.new(klass) do
          self.table_name = "products"
          include JsonAttribute::Record
          json_attribute :new_value, :integer, default: "NEW_DEFAULT_VALUE", store_key: :_new_store_key
        end
      end
      let(:subklass_instance) { subklass.new }

      it "includes default values from the parent in the jsonb hash with the correct store keys" do
        expect(subklass_instance.value).to eq("DEFAULT_VALUE")
        expect(subklass_instance.new_value).to eq("NEW_DEFAULT_VALUE")
        expect(subklass_instance.json_attributes).to eq("_store_key" => "DEFAULT_VALUE", "_new_store_key" => "NEW_DEFAULT_VALUE")
      end
    end
  end
end
