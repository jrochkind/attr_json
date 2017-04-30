require 'spec_helper'

RSpec.describe JsonAttribute::Record::QueryScopes do
  let(:klass) do
    Class.new(ActiveRecord::Base) do
      include JsonAttribute::Record
      include JsonAttribute::Record::QueryScopes

      self.table_name = "products"
      json_attribute :str, :string
      json_attribute :int, :integer
      json_attribute :int_array, :integer, array: true
      json_attribute :int_with_default, :integer, default: 5
    end
  end

  let(:instance) { klass.new }

  describe "searching for nil value" do
    it "finds value with nil" do
      instance.str = nil
      instance.save!

      result = klass.jsonb_contains(str: nil).last
      expect(result).to eq(instance)
    end

    # Don't really know if this is desirable or not, but it's
    # the most natural implementation, so we'll go with it for now.
    it "does not find value with no value set" do
      instance.save!

      result = klass.jsonb_contains(str: nil).last
      expect(result).to be_nil
    end
  end

  describe "#jsonb_contains" do
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
            include JsonAttribute::Record::QueryScopes

            self.table_name = "products"
            json_attribute :value, type
          end
        end
        it "can query for already cast #{type}" do
          instance.value = cast_value
          instance.save!

          result = klass.jsonb_contains(value: cast_value).last

          expect(result).to eq(instance)
        end
        it "can cast to query for #{type}" do
          instance.value = cast_value
          instance.save!

          result = klass.jsonb_contains(value: uncast_value).last

          expect(result).to eq(instance)
        end
      end
    end

    describe "array of primitives" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record
          include JsonAttribute::Record::QueryScopes

          self.table_name = "products"
          json_attribute :value, :string, array: true
        end
      end
      before do
        instance.value = ["one", "two", "three"]
        instance.save!
      end
      it "matches any element in array with single arg query" do
        result = klass.jsonb_contains(value: "one").first
        expect(result).to eq(instance)
      end
      # this is kind of just what the natural implementation does, but
      # let's call it intentional?
      it "matches when ALL of array query match" do
        result = klass.jsonb_contains(value: ["one", "two"]).first
        expect(result).to eq(instance)
      end
      it "does not match with a non-matching element in query array" do
        result = klass.jsonb_contains(value: ["one", "nonexisting"]).first
        expect(result).to be_nil
      end
    end

    describe "multi-column query" do
      let(:klass) do
        Class.new(ActiveRecord::Base) do
          include JsonAttribute::Record
          include JsonAttribute::Record::QueryScopes

          self.table_name = "products"
          json_attribute :str, :string
          json_attribute :int, :integer
        end
      end
      it "boolean and's" do
        instance.str = "str"
        instance.int = 101
        instance.save!

        result = klass.jsonb_contains(str: "str", int: 101).last
        expect(result).to eq(instance)
      end
      it "can fail to find a record" do
        instance.str = "str"
        instance.int = 101
        instance.save!

        result = klass.jsonb_contains(str: "str", int: 901).last
        expect(result).to be_nil
      end
    end
  end
end
