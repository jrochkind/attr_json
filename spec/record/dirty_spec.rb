RSpec.describe JsonAttribute::Record::Dirty do
  let(:klass) do
    Class.new(ActiveRecord::Base) do
      include JsonAttribute::Record
      include JsonAttribute::Record::Dirty

      self.table_name = "products"
      json_attribute :str, :string
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
    end
  end
end