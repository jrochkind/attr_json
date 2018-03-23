RSpec.describe JsonAttribute::Record::Dirty do
  let(:model_class) do
    Class.new do
      include JsonAttribute::Model

      json_attribute :str, :string
      json_attribute :int, :integer
    end
  end

  let(:klass) do
    # really hard to get the class def closure to capture the rspec
    # `let` for some reason, but this works.
    model_class_type = model_class.to_type

    Class.new(ActiveRecord::Base) do
      include JsonAttribute::Record
      include JsonAttribute::Record::Dirty

      self.table_name = "products"
      json_attribute :str, :string
      json_attribute :int, :integer
      json_attribute :str_array, :string, array: true
      json_attribute :embedded, model_class_type
    end
  end
  let(:instance) { klass.new }
  let(:changes) { instance.json_attribute_changes }

  describe "simple" do
    describe "new untouched object" do
      it "has no changes" do
        expect(changes.saved_change_to_attribute?(:str)).to be false
        expect(changes.saved_change_to_str?).to be false

        expect(changes.saved_change_to_attribute(:str)).to be nil
        expect(changes.saved_change_to_str).to be nil

        expect(changes.attribute_before_last_save(:str)).to be nil
        expect(changes.str_before_last_save).to be nil

        expect(changes.changes_to_save).to eq({})
        expect(changes.has_changes_to_save?).to be false
        expect(changes.changed_attribute_names_to_save).to eq([])


        expect(changes.will_save_change_to_attribute?(:str)).to be false
        expect(changes.will_save_change_to_str?).to be false

        expect(changes.attribute_change_to_be_saved(:str)).to be nil
        expect(changes.str_change_to_be_saved).to be nil

        expect(changes.attribute_in_database(:str)).to be nil
        expect(changes.str_in_database).to be nil

        expect(changes.saved_changes).to eq({})
        expect(changes.saved_changes?).to be false
        expect(changes.attributes_in_database).to eq({})
      end
    end

    describe "unsaved with changes" do
      let(:instance) { klass.new().tap { |i| i.str = "new"} }

      it "has changes" do
        expect(changes.saved_change_to_attribute?(:str)).to be false
        expect(changes.saved_change_to_attribute(:str)).to be nil
        expect(changes.attribute_before_last_save(:str)).to be nil
        expect(changes.changes_to_save).to eq('str' => [nil, "new"])
        expect(changes.has_changes_to_save?).to be true
        expect(changes.changed_attribute_names_to_save).to eq(["str"])

        expect(changes.will_save_change_to_attribute?(:str)).to be true
        expect(changes.attribute_change_to_be_saved(:str)).to eq [nil, "new"]
        expect(changes.attribute_in_database(:str)).to be nil
        expect(changes.saved_changes).to eq({})
        expect(changes.saved_changes?).to be false
        expect(changes.attributes_in_database).to eq({'str' => nil})
      end

      it "does not have changes for untouched json attribute" do
        expect(changes.saved_change_to_attribute?(:int)).to be false
        expect(changes.saved_change_to_attribute(:int)).to be nil
        expect(changes.attribute_before_last_save(:int)).to be nil

        expect(changes.attribute_change_to_be_saved(:int)).to be nil
        expect(changes.attribute_in_database(:int)).to be nil
        expect(changes.will_save_change_to_attribute?(:int)).to be false
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
        expect(changes.saved_change_to_attribute?(:str)).to be true
        expect(changes.saved_change_to_attribute(:str)).to eq [nil, "old"]
        expect(changes.attribute_before_last_save(:str)).to be nil
        expect(changes.changes_to_save).to eq('str' => ["old", "new"])
        expect(changes.has_changes_to_save?).to be true
        expect(changes.changed_attribute_names_to_save).to eq(["str"])

        expect(changes.will_save_change_to_attribute?(:str)).to be true
        expect(changes.attribute_change_to_be_saved(:str)).to eq ["old", "new"]
        expect(changes.attribute_in_database(:str)).to eq "old"
        expect(changes.saved_changes).to eq('str' => [nil, "old"])
        expect(changes.saved_changes?).to be true
        expect(changes.attributes_in_database).to eq('str' => 'old')
      end

      it "does not have changes for untouched json attribute" do
        expect(changes.saved_change_to_attribute?(:int)).to be false
        expect(changes.saved_change_to_attribute(:int)).to be nil
        expect(changes.attribute_before_last_save(:int)).to be nil

        expect(changes.will_save_change_to_attribute?(:int)).to be false
        expect(changes.attribute_change_to_be_saved(:int)).to be nil
        expect(changes.attribute_in_database(:int)).to be nil
      end
    end
  end

  describe "unknown attribute" do
    it "returns nil without complaining, like ordinary AR attributes" do
      expect(changes.saved_change_to_attribute?(:unknown)).to be nil
      expect(changes.saved_change_to_attribute(:unknown)).to be nil
      expect(changes.attribute_before_last_save(:unknown)).to be nil
      expect(changes.changed_attribute_names_to_save).to eq([])

      expect(changes.will_save_change_to_attribute?(:unknown)).to be nil
      expect(changes.attribute_change_to_be_saved(:unknown)).to eq nil
      expect(changes.attribute_in_database(:unknown)).to be nil
      expect(changes.attributes_in_database).to eq({})
    end
  end

  describe "array" do
    describe "after save, with more unsaved changes" do
      let(:instance) do
        klass.new(str_array: ["old1", "old2"]).tap do |i|
          i.save
          i.str_array << "new1"
        end
      end

      it "has all changes" do
        expect(changes.saved_change_to_attribute?(:str_array)).to be true
        expect(changes.saved_change_to_attribute(:str_array)).to eq [nil, ["old1", "old2"]]
        expect(changes.attribute_before_last_save(:str_array)).to be nil
        expect(changes.saved_changes).to eq('str_array' => [nil, ["old1", "old2"]])
        expect(changes.saved_changes?).to be true
        expect(changes.attributes_in_database).to eq('str_array' => ["old1", "old2"])

        expect(changes.will_save_change_to_attribute?(:str_array)).to be true
        expect(changes.attribute_change_to_be_saved(:str_array)).to eq [["old1", "old2"], ["old1", "old2", "new1"]]
        expect(changes.attribute_in_database(:str_array)).to eq ["old1", "old2"]
        expect(changes.changes_to_save).to eq('str_array' => [["old1", "old2"], ["old1", "old2", "new1"]])
        expect(changes.has_changes_to_save?).to be true
        expect(changes.changed_attribute_names_to_save).to eq(["str_array"])
      end
    end
  end

  describe "embedded" do
    describe "after save, with more unsaved changes" do
      let(:instance) do
        klass.new(embedded: {str: "oldstr", int: 0}).tap do |i|
          i.save
          i.embedded.str = "newstr"
        end
      end
      let(:orig_model_eq) { model_class.new(str: "oldstr", int: 0) }
      let(:new_model_eq) { model_class.new(str: "newstr", int: 0) }

      it "has all changes" do
        expect(changes.saved_change_to_attribute?(:embedded)).to be true
        expect(changes.saved_change_to_attribute(:embedded)).to eq [nil, orig_model_eq]
        expect(changes.attribute_before_last_save(:embedded)).to be nil
        expect(changes.saved_changes).to eq('embedded' => [nil, orig_model_eq])
        expect(changes.saved_changes?).to be true


        expect(changes.attribute_change_to_be_saved(:embedded)).to eq [orig_model_eq, new_model_eq]
        expect(changes.will_save_change_to_attribute?(:embedded)).to be true
        expect(changes.attribute_in_database(:embedded)).to eq orig_model_eq
        expect(changes.changes_to_save).to eq('embedded' => [orig_model_eq, new_model_eq])
        expect(changes.has_changes_to_save?).to be true
        expect(changes.changed_attribute_names_to_save).to eq(["embedded"])
        expect(changes.attributes_in_database).to eq('embedded' => orig_model_eq)
      end
    end
  end

  describe "ordinary db attributes" do
    let(:instance) do
      klass.new(string_type: "old").tap do |i|
        i.save
        i.string_type = "new"
      end
    end
    describe "with merged" do
      let(:changes) { instance.json_attribute_changes.merged }
      it "can see changes to ordinary attr" do
        expect(changes.saved_change_to_attribute(:string_type)).to eq [nil, "old"]
        expect(changes.saved_change_to_attribute?(:string_type)).to be true
        expect(changes.attribute_before_last_save(:string_type)).to be nil
        expect(changes.changes_to_save).to eq('string_type' => ["old", "new"])
        expect(changes.has_changes_to_save?).to be true
        expect(changes.changed_attribute_names_to_save).to eq(["string_type"])

        expect(changes.attribute_change_to_be_saved(:string_type)).to eq ["old", "new"]
        expect(changes.will_save_change_to_attribute?(:string_type)).to be true
        expect(changes.attribute_in_database(:string_type)).to eq "old"
        expect(changes.saved_changes?).to be true
        expect(changes.attributes_in_database).to eq('string_type' => 'old')
        expect(changes.saved_changes).to eq(instance.saved_changes)
      end
    end

    describe "with merged(containers: false) and both kinds of changes" do
      let(:instance) do
        klass.new(string_type: "old_ordinary", str: "old_json").tap do |i|
          i.save
          i.str = "new_json"
          i.string_type = "new_ordinary"
        end
      end
      let(:changes) { instance.json_attribute_changes.merged(containers: false) }

      it "has the right changes" do
        expect(changes.saved_change_to_attribute(:string_type)).to eq [nil, "old_ordinary"]
        expect(changes.saved_change_to_attribute(:str)).to eq [nil, "old_json"]
        expect(changes.saved_change_to_attribute(:json_attributes)).to be nil

        expect(changes.saved_change_to_attribute?(:string_type)).to be true
        expect(changes.saved_change_to_attribute?(:str)).to be true
        expect(changes.saved_change_to_attribute?(:json_attributes)).to be nil

        expect(changes.attribute_before_last_save(:string_type)).to be nil
        expect(changes.attribute_before_last_save(:str)).to be nil
        expect(changes.attribute_before_last_save(:json_attributes)).to be nil

        expect(changes.changes_to_save).to eq(
          'string_type' => ["old_ordinary", "new_ordinary"],
          'str'         => ["old_json", "new_json"]
        )

        expect(changes.has_changes_to_save?).to be true
        expect(changes.changed_attribute_names_to_save).to eq(["string_type", "str"])

        expect(changes.attribute_change_to_be_saved(:string_type)).to eq ["old_ordinary", "new_ordinary"]
        expect(changes.attribute_change_to_be_saved(:str)).to eq ["old_json", "new_json"]
        expect(changes.attribute_before_last_save(:json_attributes)).to be nil

        expect(changes.will_save_change_to_attribute?(:string_type)).to be true
        expect(changes.will_save_change_to_attribute?(:str)).to be true
        expect(changes.will_save_change_to_attribute?(:json_attributes)).to be nil

        expect(changes.attribute_in_database(:string_type)).to eq "old_ordinary"
        expect(changes.attribute_in_database(:str)).to eq "old_json"
        expect(changes.attribute_in_database(:json_attributes)).to be nil

        expect(changes.saved_changes?).to be true
        expect(changes.attributes_in_database).to eq(
          'string_type' => 'old_ordinary',
          'str'         => 'old_json'
        )
        expect(changes.saved_changes).to eq(
          instance.saved_changes.except("json_attributes").merge(
            'str' => [nil, "old_json"]
          )
        )
      end
    end
  end
end
