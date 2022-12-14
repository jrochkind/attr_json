require 'spec_helper'

RSpec.describe AttrJson::Type::PolymorphicModel do
  let(:model1) do
    Model1 = Class.new do
      include AttrJson::Model
      attr_json :str, :string
      attr_json :int, :integer
    end
  end

  let(:model2) do
    Model2 = Class.new do
      include AttrJson::Model
      attr_json :str, :string
      attr_json :bool, :boolean
    end
  end

  let(:klass) do
    # workaround to ruby scope weirdness
    our_model1, our_model2 = model1, model2
    TestRecord = Class.new(ActiveRecord::Base) do
      include AttrJson::Record
      include AttrJson::Record::QueryScopes

      self.table_name = "products"

      attr_json :one_poly, AttrJson::Type::PolymorphicModel.new(our_model1, our_model2)
      attr_json :many_poly, AttrJson::Type::PolymorphicModel.new(our_model1, our_model2), array: true
    end
  end

  # remove those constants we created for test classes
  after do
    Object.send(:remove_const, :Model1) if defined?(Model1)
    Object.send(:remove_const, :Model2) if defined?(Model2)
    Object.send(:remove_const, :TestRecord) if defined?(TestRecord)
  end

  let(:instance) { klass.new }

  describe "conflicting type key" do
    let(:model1) do
      Model1 = Class.new do
        include AttrJson::Model
        attr_json :str, :string
        attr_json :int, :integer
        attr_json :type, :string
      end
    end

    it "it raises" do
      expect { klass }.to raise_error ArgumentError
    end
  end

  describe "define with non-model type" do
    let(:klass) do
      # workaround to ruby scope weirdness
      our_model1 = model1
      TestRecord = Class.new(ActiveRecord::Base) do
        include AttrJson::Record
        self.table_name = "products"

        attr_json :one_poly, AttrJson::Type::PolymorphicModel.new(our_model1, :string)
      end
    end

    it "raises" do
      expect { klass }.to raise_error ArgumentError
    end
  end

  describe "single poly" do
    it "sets and saves model" do
      instance.one_poly = model1.new(str: "str", int: 12)
      instance.save!
      instance.reload

      expect(instance.one_poly).to eq model1.new(str: "str", int: 12)
    end

    it "can set to nil though" do
      instance.save!
      expect(instance.one_poly).to be(nil)

      instance.one_poly = model1.new
      instance.save!

      instance.one_poly = nil
      instance.save!
      expect(instance.one_poly).to be(nil)
    end

    it "can set hash with type key" do
      instance.one_poly = { str: "str", int: 12, type: "Model1" }
      instance.save!
      instance.reload

      expect(instance.one_poly).to eq model1.new(str: "str", int: 12)
    end

    it "has a type name" do
      expect(AttrJson::Type::PolymorphicModel.new(model1, model2).type).to eq :any_of_model1_model2
    end
  end

  describe "array of poly" do
    it "sets and saves models" do
      instance.many_poly = [model1.new(str: "str", int: 12), model2.new(str: "str", bool: true)]
      instance.save!
      instance.reload
      expect(instance.many_poly).to eq [model1.new(str: "str", int: 12), model2.new(str: "str", bool: true)]
    end

    it "can set hashes with type key" do
      instance.many_poly = [{ str: "str", int: 12, type: "Model1" }, { str: "str", bool: true, type: "Model2" }]
      instance.save!
      instance.reload

      expect(instance.many_poly).to eq [model1.new(str: "str", int: 12), model2.new(str: "str", bool: true)]
    end
  end

  describe "assigning via json_attributes" do
    it "allows assigning via raw hash object" do
      instance.json_attributes = {
        "one_poly": {"int": 12, "str": "str", "type": "Model1"},
        "many_poly": [
          {"int": 12, "str": "str", "type": "Model1"},
          {"str": "str", "bool": true, "type": "Model2"}
        ]
      }
      instance.save
      # TODO: assert assignment worked correctly
    end
  end

  describe "bad types" do
    it "raises on hash set with no type key" do
      expect { instance.one_poly = { str: "str", int: 12 } }.to raise_error AttrJson::Type::PolymorphicModel::TypeError
    end

    it "raises on hash set with bad type key" do
      expect { instance.one_poly = { str: "str", int: 12, type: "Nope" } }.to raise_error AttrJson::Type::PolymorphicModel::TypeError
    end

    it "raises on set with bad class" do
      expect { instance.one_poly = "foo bar this is a string" }.to raise_error AttrJson::Type::PolymorphicModel::TypeError
    end

    it "raises on save for sneaky hash set with no type key" do
      instance.json_attributes["one_poly"] = { str: "str", int: 12 }
      expect { instance.save! }.to raise_error AttrJson::Type::PolymorphicModel::TypeError
    end

    it "raises on save for sneaky hash set with bad type key" do
      instance.json_attributes["one_poly"] = { str: "str", int: 12, type: "Nope" }
      expect { instance.save! }.to raise_error AttrJson::Type::PolymorphicModel::TypeError
    end

    it "raises on save for sneaky hash set to bad type" do
      instance.json_attributes["one_poly"] = "this is a string not a hash"
      expect { instance.save! }.to raise_error AttrJson::Type::PolymorphicModel::TypeError
    end

    describe "bad values in database" do
      let (:bad_value) { {"one_poly" => "foo"} }
      before do
        # hard to get bad values in the db, heh
        instance.save
        ActiveRecord::Base.connection.execute("update products set json_attributes='#{bad_value.to_json}' where id=#{instance.id}")
      end

      it "can load without error" do
        instance.reload
      end

      it "can show before_type_cast without error" do
        instance.reload
        expect(JSON.parse(instance.json_attributes_before_type_cast)).to eq bad_value
      end

      it "errors on accessing attribute" do
        instance.reload
        expect { instance.one_poly }.to raise_error AttrJson::Type::PolymorphicModel::TypeError
      end

      # Not so much intentional design, but this is what it does...
      it "errors on accessing container" do
        instance.reload
        expect { instance.json_attributes }.to raise_error AttrJson::Type::PolymorphicModel::TypeError
      end
    end
  end

  describe "jsonb_contains" do
    it "can create keypath query" do
      sql = klass.jsonb_contains("one_poly.bool" => true).to_sql
      expect(sql).to include "products.json_attributes @> ('{\"one_poly\":{\"bool\":true}}')"
    end
    it "can create keypath query with type" do
      sql = klass.jsonb_contains("one_poly" => {"bool" => true, "type" => "Model2"}).to_sql
      expect(sql).to include "products.json_attributes @> ('{\"one_poly\":{\"bool\":true,\"type\":\"Model2\"}}')"
    end
    it "can create keypath query with model arg" do
      sql = klass.jsonb_contains("one_poly" => model2.new(bool: true)).to_sql
      expect(sql).to include "products.json_attributes @> ('{\"one_poly\":{\"bool\":true,\"type\":\"Model2\"}}')"
    end
  end

  describe "not_jsonb_contains" do
    it "can create keypath query" do
      sql = klass.not_jsonb_contains("one_poly.bool" => true).to_sql
      expect(sql).to match(/WHERE \(?NOT \(products.json_attributes @> \('{\"one_poly\":{\"bool\":true}}'\)/)
    end
    it "can create keypath query with type" do
      sql = klass.not_jsonb_contains("one_poly" => {"bool" => true, "type" => "Model2"}).to_sql
      expect(sql).to match(/WHERE \(?NOT \(products.json_attributes @> \('{\"one_poly\":{\"bool\":true,\"type\":\"Model2\"}}'\)/)
    end
    it "can create keypath query with model arg" do
      sql = klass.not_jsonb_contains("one_poly" => model2.new(bool: true)).to_sql
      expect(sql).to match(/WHERE \(?NOT \(products.json_attributes @> \('{\"one_poly\":{\"bool\":true,\"type\":\"Model2\"}}'\)/)
    end
  end
end
