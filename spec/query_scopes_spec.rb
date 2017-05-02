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

  describe "multiple container attributes" do
    # let's give em the same store key to make it really challenging?
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record
        include JsonAttribute::Record::QueryScopes

        self.table_name = "products"
        json_attribute :str_json_attributes, :string, store_key: "_str"
        json_attribute :str_other_attributes, :string, store_key: "_str", container_attribute: "other_attributes"
      end
    end
    before do
      instance.str_json_attributes = "j_value"
      instance.str_other_attributes = "o_value"
      instance.save!
    end
    it "still queries okay" do
      query = klass.jsonb_contains(str_json_attributes: "j_value", str_other_attributes: "o_value")

      expect(query.to_sql).to include "products.json_attributes @> ('{\"_str\":\"j_value\"}'"
      expect(query.to_sql).to include "products.other_attributes @> ('{\"_str\":\"o_value\"}'"

      result = query.last
      expect(result).to eq(instance)
    end
  end

  describe "nested models" do
    # why not a crazy recursive one? I think we can do that.
    let(:model_class) do
      Class.new do
        include JsonAttribute::Model

        json_attribute :str, :string
        json_attribute :model, self.to_type
        json_attribute :int_array, :integer, array: true
        json_attribute :int_with_default, :integer, default: 5
        json_attribute :datetime, :datetime
      end
    end
    let(:klass) do
      model_class_type = model_class.to_type
      Class.new(ActiveRecord::Base) do
        include JsonAttribute::Record
        include JsonAttribute::Record::QueryScopes

        self.table_name = "products"
        json_attribute :model, model_class_type
        json_attribute :int, :integer
      end
    end
    it "can create keypath query" do
      sql = klass.jsonb_contains("model.str" => "foo").to_sql
      expect(sql).to include "products.json_attributes @> ('{\"model\":{\"str\":\"foo\"}}')"
    end
    it "can find object" do
      instance.model = {}
      instance.model.str = "foo"
      instance.save!

      result = klass.jsonb_contains("model.str" => "foo").first
      expect(result).to eq(instance)
    end
    it "doesn't error on find if there's no hash at all model" do
      instance.save!
      # our casting is sometimes insisting on a {} there, we want to
      # to make sure it's really null in the db, and it doesn't complain
      # on our search.
      klass.update_all("json_attributes = null")
      # precondition for our test, sorry, hacky
      raw_result = ActiveRecord::Base.connection.execute("select json_attributes from #{klass.table_name} where id = #{instance.id}").first
      expect(raw_result["json_attributes"]).to be_nil

      expect(klass.jsonb_contains("model.str" => "foo").first).to be_nil
    end
  end


end
