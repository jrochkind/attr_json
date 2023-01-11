require 'spec_helper'

#TODO tests could use a lot of DRYing up, maybe with shared example groups
RSpec.describe AttrJson::Record::QueryScopes do
  let(:klass) do
    Class.new(ActiveRecord::Base) do
      include AttrJson::Record

      self.table_name = "products"
      attr_json :str, :string
      attr_json :int, :integer
      attr_json :int_array, :integer, array: true
      attr_json :int_with_default, :integer, default: 5
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
      [:decimal, BigDecimal("10.01"), "10.0100"],
      [:boolean, true, "t"],
      [:date, Date.parse("2017-04-28"), "2017-04-28"],
      [:datetime, DateTime.parse("2017-04-04 04:45:00").to_time, "2017-04-04T04:45:00Z"],
      [:float, 45.45, "45.45"]
    ].each do |type, cast_value, uncast_value|
      describe "for primitive type #{type}" do
        let(:klass) do
          Class.new(ActiveRecord::Base) do
            include AttrJson::Record::Base
            include AttrJson::Record::QueryScopes

            self.table_name = "products"
            attr_json :value, type
          end
        end
        it "can query with exact type" do
          instance.value = cast_value
          instance.save!

          result = klass.jsonb_contains(value: cast_value).last

          expect(result).to eq(instance)
        end
        it "can cast value for query" do
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
          include AttrJson::Record::Base
          include AttrJson::Record::QueryScopes

          self.table_name = "products"
          attr_json :value, :string, array: true
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
          include AttrJson::Record::Base
          include AttrJson::Record::QueryScopes

          self.table_name = "products"
          attr_json :str, :string
          attr_json :int, :integer
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

  describe "#not_jsonb_contains" do
    it 'generates a negated query' do
      query = klass.not_jsonb_contains(str: 'foo')

      expect(query.to_sql).to match(/WHERE \(?NOT \(products.json_attributes @> \('{"str":"foo"}'\)::jsonb\)/)
    end
  end

  describe "multiple container attributes" do
    # let's give em the same store key to make it really challenging?
    let(:klass) do
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record::Base
        include AttrJson::Record::QueryScopes

        self.table_name = "products"
        attr_json :str_attr_jsons, :string, store_key: "_str"
        attr_json :str_other_attributes, :string, store_key: "_str", container_attribute: "other_attributes"
      end
    end
    before do
      instance.str_attr_jsons = "j_value"
      instance.str_other_attributes = "o_value"
      instance.save!
    end
    it "still queries okay" do
      query = klass.jsonb_contains(str_attr_jsons: "j_value", str_other_attributes: "o_value")

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
        include AttrJson::Model

        attr_json :str, :string
        attr_json :model, self.to_type
        attr_json :int_array, :integer, array: true
        attr_json :int_with_default, :integer, default: 5
        attr_json :datetime, :datetime
      end
    end
    let(:klass) do
      model_class_type = model_class.to_type
      Class.new(ActiveRecord::Base) do
        include AttrJson::Record::Base
        include AttrJson::Record::QueryScopes

        self.table_name = "products"
        attr_json :model, model_class_type
        attr_json :int, :integer
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

    describe "double-nested model with array" do
      let(:lang_and_val_class) do
        Class.new do
          include AttrJson::Model

          attr_json :lang, :string, default: "en"
          attr_json :value, :string
        end
      end
      let(:some_labels_class) do
        lang_and_val_type = lang_and_val_class.to_type
        Class.new do
          include AttrJson::Model

          attr_json :hello, lang_and_val_type, array: true
        end
      end
      let(:klass) do
        some_labels_class_type = some_labels_class.to_type
        Class.new(ActiveRecord::Base) do
          self.table_name = "products"
          include AttrJson::Record::Base
          include AttrJson::Record::QueryScopes

          attr_json :my_labels, some_labels_class_type
        end
      end
      before do
        instance.my_labels = {}
        instance.my_labels.hello = [{lang: 'en', value: 'hello'}, {lang: 'es', value: 'hola'}]
        instance.save!
      end

      describe ", complete key path" do
        let(:relation) { klass.jsonb_contains("my_labels.hello.lang" => "en") }

        it "generates query okay" do
          expect(relation.to_sql).to include "(products.json_attributes @> ('{\"my_labels\":{\"hello\":[{\"lang\":\"en\"}]}}')::jsonb)"
        end
        it "fetches" do
          expect(relation.count).to eq 1
          expect(relation.first).to eq(instance)
        end
      end

      describe ", hash value in query" do
        let(:relation) { klass.jsonb_contains("my_labels.hello" => {lang: "en"}) }

        it "generates query okay" do
          expect(relation.to_sql).to include "(products.json_attributes @> ('{\"my_labels\":{\"hello\":[{\"lang\":\"en\"}]}}')::jsonb)"
        end

        it "fetches" do
          expect(relation.count).to eq 1
          expect(relation.first).to eq(instance)
        end
      end

      describe "multiple query attributes" do
        let(:relation) { klass.jsonb_contains("my_labels.hello.lang" => "en", "my_labels.hello.value" => "hello") }

        # TODO. We need a custom deep_merge in query builder, bah.
        # Semantics are actually not entirely clear. Did the user mean
        # the same structure needs to have `{lang: 'en', {value: 'hello'}}`,
        # or were they asking for an object that might have one of those pairs
        # in one hash, and the other in another, in the array? I think the former
        # probably, use separate jsonb_contains calls for the latter.
        it "generates query okay" do
          expect(relation.to_sql).to include "(products.json_attributes @> ('{\"my_labels\":{\"hello\":[{\"lang\":\"en\",\"value\":\"hello\"}]}}')::jsonb)"
        end

        it "fetches" do
          expect(relation.count).to eq 1
          expect(relation.first).to eq(instance)
        end
      end

    end
  end
end
