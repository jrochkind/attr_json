# Ordinary Rails attribute dirty tracking. How well can we get it to work, even
# under mutation of mutable objects
RSpec.describe "ActiveRecord dirty tracking" do
  let(:model_class) do
    Class.new do
      include AttrJson::Model

      attr_json :str, :string
      attr_json :int, :integer
    end
  end

  let(:ordinary_klass) do
    Class.new(ActiveRecord::Base) do
      self.table_name = "products"

      attribute :other, :json
    end
  end

  let(:klass) do
    # really hard to get the class def closure to capture the rspec
    # `let` for some reason, but this works.
    model_class_type = model_class.to_type

    Class.new(ActiveRecord::Base) do
      include AttrJson::Record

      self.table_name = "products"
      attr_json :str, :string
      attr_json :int, :integer
      attr_json :bool, :boolean
      # just to make our changes more sane, set no default
      attr_json :str_array, :string, array: true, default: AttrJson::AttributeDefinition::NO_DEFAULT_PROVIDED
      attr_json :embedded, model_class_type
    end
  end
  let(:instance) { klass.new }

  let(:initial_tracked_container_value) do
    # We set a default of empty hash `{}`.  Up to Rails 7.1, Rails ignores
    # the default in dirty tracking, and consideers the initial value nil -- but
    # post Rails 7.1, Rails dirty tracking _starts_ at `{}`. We don't consider it a bug,
    # the new behavior is probably better, we just go with it in tests either way.
    if Gem::Version.new(Rails::VERSION::STRING) >= Gem::Version.new("7.2.0.alpha")
      {}
    else
      nil
    end
  end

  describe "simple" do
    describe "new untouched object" do
      it "has no changes" do
        expect(instance.saved_change_to_attribute?(:str)).to be false
        expect(instance.saved_change_to_str?).to be false

        expect(instance.saved_change_to_attribute(:str)).to be nil
        expect(instance.saved_change_to_str).to be nil

        expect(instance.attribute_before_last_save(:str)).to be nil
        expect(instance.str_before_last_save).to be nil


        if initial_tracked_container_value == {}
          expect(instance.changes_to_save).to eq({})
          expect(instance.has_changes_to_save?).to be false
          expect(instance.changed_attribute_names_to_save).to eq([])
          expect(instance.attributes_in_database).to eq({})
        else
          expect(instance.changes_to_save).to eq({ "json_attributes" => [nil, {}] })
          expect(instance.has_changes_to_save?).to be true
          expect(instance.changed_attribute_names_to_save).to eq(["json_attributes"])
          expect(instance.attributes_in_database).to eq({ "json_attributes" => nil })
        end



        expect(instance.will_save_change_to_attribute?(:str)).to be false
        expect(instance.will_save_change_to_str?).to be false

        expect(instance.attribute_change_to_be_saved(:str)).to be nil
        expect(instance.str_change_to_be_saved).to be nil

        expect(instance.attribute_in_database(:str)).to be nil
        expect(instance.str_in_database).to be nil

        expect(instance.saved_changes).to eq({})
        expect(instance.saved_changes?).to be false

      end
    end

    describe "unsaved with changes" do
      let(:instance) { klass.new().tap { |i| i.str = "new"} }

      it "has changes" do
        expect(instance.saved_change_to_attribute?(:str)).to be false
        expect(instance.saved_change_to_attribute(:str)).to be nil
        expect(instance.attribute_before_last_save(:str)).to be nil
        expect(instance.changes_to_save).to eq(
          'json_attributes' => [initial_tracked_container_value, { "str" => "new" }],
          'str' => [nil, "new"]
        )
        expect(instance.has_changes_to_save?).to be true
        expect(instance.changed_attribute_names_to_save).to match_array(["str", "json_attributes"])

        expect(instance.will_save_change_to_attribute?(:str)).to be true
        expect(instance.attribute_change_to_be_saved(:str)).to eq [nil, "new"]
        expect(instance.attribute_in_database(:str)).to be nil
        expect(instance.saved_changes).to eq({})
        expect(instance.saved_changes?).to be false
        expect(instance.attributes_in_database).to eq({'json_attributes' => initial_tracked_container_value, 'str' => nil})
      end

      it "does not have changes for untouched json attribute" do
        expect(instance.saved_change_to_attribute?(:int)).to be false
        expect(instance.saved_change_to_attribute(:int)).to be nil
        expect(instance.attribute_before_last_save(:int)).to be nil

        expect(instance.attribute_change_to_be_saved(:int)).to be nil
        expect(instance.attribute_in_database(:int)).to be nil
        expect(instance.will_save_change_to_attribute?(:int)).to be false
      end

    end

    describe "after save, with more unsaved changes" do
      let(:instance) do
        klass.new(str: "old").tap do |i|
          i.save
          i.str = "new"
        end
      end

      it "has all changes" do
        expect(instance.saved_change_to_attribute?(:str)).to be true
        expect(instance.saved_change_to_attribute(:str)).to eq [nil, "old"]
        expect(instance.attribute_before_last_save(:str)).to be nil
        expect(instance.changes_to_save).to eq(
          'str' => ["old", "new"],
          'json_attributes' => [{"str"=>"old"}, {"str"=>"new"}]
        )
        expect(instance.has_changes_to_save?).to be true
        expect(instance.changed_attribute_names_to_save).to match_array(["json_attributes", "str"])

        expect(instance.will_save_change_to_attribute?(:str)).to be true
        expect(instance.attribute_change_to_be_saved(:str)).to eq ["old", "new"]
        expect(instance.attribute_in_database(:str)).to eq "old"
        expect(instance.saved_changes.except("id")).to eq(
          'str' => [nil, "old"],
          "json_attributes" => [initial_tracked_container_value, {"str"=>"old"}]
        )
        expect(instance.saved_changes?).to be true
        expect(instance.attributes_in_database).to eq(
          'str' => 'old',
          "json_attributes" => {"str"=>"old"}
        )
      end

      it "does not have changes for untouched json attribute" do
        expect(instance.saved_change_to_attribute?(:int)).to be false
        expect(instance.saved_change_to_attribute(:int)).to be nil
        expect(instance.attribute_before_last_save(:int)).to be nil

        expect(instance.will_save_change_to_attribute?(:int)).to be false
        expect(instance.attribute_change_to_be_saved(:int)).to be nil
        expect(instance.attribute_in_database(:int)).to be nil
      end
    end

    describe "multiple attributes in place" do
      it "keeps them separate" do
        # this is a regression from our custom dirty tracking
        obj = klass.create!
        obj.int = 101
        obj.save!

        obj.str = "value"
        expect(obj.will_save_change_to_int?).to be false
        expect(obj.will_save_change_to_str?).to be true
      end
    end

    describe "boolean attribute dirty tracking" do
      it "does not report a change when assigning false to false" do
        instance.bool = false
        instance.save!
        instance.reload
        expect(instance.bool).to be false
        expect(instance.changes.empty?).to be true

        instance.assign_attributes({ str: "new", bool: false })
        expect(instance.bool_changed?).to be false
        expect(instance.str_changed?).to be true
      end
    end
  end

  describe "array" do
    it "is the same object in rails attributes and json hash" do
      instance = klass.new
      expect(instance.read_attribute(:str_array).equal?(  instance.json_attributes["str_array"])).to be true
    end

    describe "after assignment" do
      it "is the same object in rails attributes and json hash" do
        obj = klass.new
        obj.str_array = ["one", "ten"]
        expect(obj.read_attribute(:str_array).equal?(  obj.json_attributes["str_array"])).to be true
      end
    end

    describe "after a fetch" do
      let(:instance) do
        i = klass.create!(str_array: ["old1", "old2"])
        klass.find(i.id)
      end

      it "has same object in rails attributes and json hash" do
        expect(instance.read_attribute(:str_array).equal?(  instance.json_attributes["str_array"])).to be true
      end

      it "tracks all changes from in-place mutation" do
        instance.str_array << "new1"

        expect(instance.changed?).to be true
        expect(instance.has_changes_to_save?).to be true

        expect(instance.will_save_change_to_attribute?(:str_array)).to be true
        expect(instance.attribute_in_database(:str_array)).to eq ["old1", "old2"]
        expect(instance.attribute_change_to_be_saved(:str_array)).to eq [["old1", "old2"], ["old1", "old2", "new1"]]


        expect(instance.changed_attribute_names_to_save).to match_array(["str_array", "json_attributes"])
        expect(instance.changes_to_save).to eq(
          'str_array' => [["old1", "old2"], ["old1", "old2", "new1"]],
          "json_attributes" => [{ "str_array" => ["old1", "old2"] }, { "str_array" => ["old1", "old2", "new1"] }]
        )

        expect(instance.saved_change_to_attribute?(:str_array)).to be false
        expect(instance.saved_change_to_attribute(:str_array)).to eq nil
        expect(instance.attribute_before_last_save(:str_array)).to be nil
        expect(instance.saved_changes).to eq({})
        expect(instance.saved_changes?).to be false
        expect(instance.attributes_in_database).to eq(
          'str_array' => ["old1", "old2"],
          "json_attributes" => {"str_array"=>["old1", "old2"]}
        )
      end
    end

    describe "after a save" do
      let(:instance) do
        i = klass.new(str_array: ["old1", "old2"])
        i.save!
        i
      end

      it "has same object in rails attributes and json hash" do
        expect(instance.read_attribute(:str_array).equal?( instance.json_attributes["str_array"] )).to be true
      end

      it "tracks all changes from in-place mutations" do
        instance.str_array << "new1"

        expect(instance.changed?).to be true
        expect(instance.has_changes_to_save?).to be true

        expect(instance.will_save_change_to_attribute?(:str_array)).to be true
        expect(instance.attribute_in_database(:str_array)).to eq ["old1", "old2"]
        expect(instance.attribute_change_to_be_saved(:str_array)).to eq [["old1", "old2"], ["old1", "old2", "new1"]]


        expect(instance.changed_attribute_names_to_save).to match_array(["str_array", "json_attributes"])
        expect(instance.changes_to_save).to eq(
          'str_array' => [["old1", "old2"], ["old1", "old2", "new1"]],
          "json_attributes" => [{ "str_array" => ["old1", "old2"] }, { "str_array" => ["old1", "old2", "new1"] }]
        )

        expect(instance.saved_change_to_attribute?(:str_array)).to be true
        expect(instance.saved_change_to_attribute(:str_array)).to eq [nil, ["old1", "old2"]]
        expect(instance.attribute_before_last_save(:str_array)).to be nil
        expect(instance.saved_changes.except(:id, :json_attributes)).to eq({ "str_array" => [nil, ["old1", "old2"]]})
        expect(instance.saved_changes?).to be true
        expect(instance.attributes_in_database).to eq(
          'str_array' => ["old1", "old2"],
          "json_attributes" => {"str_array"=>["old1", "old2"]}
        )
      end
    end
  end

  describe "embedded" do
    describe "on initialization with value" do
      let(:embedded_hash) { { str: "value", int: 11 } }
      let(:embedded_model) { model_class.new(embedded_hash) }
      let(:instance) { klass.new(embedded: embedded_hash) }

      it "is the same object in rails attributes and json hash" do
        expect(instance.read_attribute(:embedded).equal?(  instance.json_attributes["embedded"])).to be true
      end

      it "knows changes" do
        expect(instance.saved_change_to_attribute?(:embedded)).to be false
        expect(instance.attribute_change_to_be_saved(:embedded)).to eq [nil, embedded_model]
      end
    end

    describe "after assignment" do
      let(:instance) do
        obj = klass.new
        obj.embedded = { str: "value", int: 11 }
        obj
      end

      it "is the same object in rails attributes and json hash" do
        expect(instance.read_attribute(:embedded).equal?(  instance.json_attributes["embedded"])).to be true

        instance.embedded = model_class.new({ str: "value", int: 11 })
        expect(instance.read_attribute(:embedded).equal?(  instance.json_attributes["embedded"])).to be true
      end
    end

    describe "after save, with more unsaved changes made as in-place mutation" do
      let(:instance) do
        klass.new(embedded: {str: "oldstr", int: 0}).tap do |i|
          i.save!
          i.embedded.str = "newstr"
        end
      end
      let(:orig_model_eq) { model_class.new(str: "oldstr", int: 0) }
      let(:new_model_eq) { model_class.new(str: "newstr", int: 0) }

      it "tracks all changes" do
        expect(instance.saved_change_to_attribute?(:embedded)).to be true
        expect(instance.saved_change_to_attribute(:embedded)).to eq [nil, orig_model_eq]
        expect(instance.attribute_before_last_save(:embedded)).to be nil

        expect(instance.saved_changes.except("id")).to eq(
          'embedded' => [nil, orig_model_eq],
          "json_attributes" => [initial_tracked_container_value, { "embedded" => orig_model_eq }]
        )
        expect(instance.saved_changes?).to be true


        expect(instance.attribute_change_to_be_saved(:embedded)).to eq [orig_model_eq, new_model_eq]
        expect(instance.will_save_change_to_attribute?(:embedded)).to be true
        expect(instance.attribute_in_database(:embedded)).to eq orig_model_eq

        expect(instance.changes_to_save).to eq(
          'json_attributes' => [{ "embedded" => orig_model_eq }, { "embedded" => new_model_eq } ],
          'embedded' => [orig_model_eq, new_model_eq]
        )

        expect(instance.has_changes_to_save?).to be true
        expect(instance.changed_attribute_names_to_save).to match_array(["embedded", "json_attributes"])
        expect(instance.attributes_in_database).to eq(
          'embedded' => orig_model_eq,
          'json_attributes' => { "embedded" => orig_model_eq }
        )
      end
    end
  end
end
