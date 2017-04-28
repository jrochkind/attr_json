require 'spec_helper'

RSpec.describe JsonAttribute::ActiveRecordModel do
  let(:klass) do
    Class.new(ActiveRecord::Base) do
      include JsonAttribute::ActiveRecordModel
      # TODO this gotta be automatic
      attribute :json_attributes, JsonAttribute::ActiveRecordModel::ContainerAttributeType.new(self)

      self.table_name = "products"
      json_attribute :str, :string
      json_attribute :int, :integer
      json_attribute :int_array, :integer, array: true
      json_attribute :int_with_default, :integer, default: 5
    end
  end
  let(:instance) { klass.new }

  it "supports types" do
    instance.str = 12
    expect(instance.str).to eq("12")
    expect(instance.json_attributes).to include("str" => "12")
    instance.save!
    instance.reload
    expect(instance.str).to eq("12")
    expect(instance.json_attributes).to include("str" => "12")


    instance.int = "12"
    expect(instance.int).to eq(12)
    expect(instance.json_attributes).to include("int" => 12)
    instance.save!
    instance.reload
    expect(instance.int).to eq(12)
    expect(instance.json_attributes).to include("int" => 12)
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

  context "defaults" do
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::ActiveRecordModel
        # TODO this gotta be automatic
        attribute :json_attributes, JsonAttribute::ActiveRecordModel::ContainerAttributeType.new(self)

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
end
