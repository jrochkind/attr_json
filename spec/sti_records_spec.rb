require 'spec_helper'

RSpec.describe AttrJson::Record do
  describe "module on main class" do
    let(:main_class) do
      # Rails STI needs a class name, so an anonymous class won't do, but
      # this will.
      stub_const(
        "TestStInheritWidget",
        Class.new(ActiveRecord::Base) do
          self.table_name = "st_inherit_widgets"

          include AttrJson::Record

          attr_json :parent_str, :string
        end
      )
    end

    let(:subclass) do
      # Rails STI needs a class name, so an anonymous class won't do, but
      # this will.
      stub_const(
        "TestSubclass",
        Class.new(main_class) do
          attr_json :str, :string
          attr_json :int_array, :integer, array: true
        end
      )
    end

    let(:subclass_inst) { subclass.new }

    it "persists data on sub-class" do
      subclass_inst.str = "foo"
      subclass_inst.int_array = [1,2,3]
      subclass_inst.parent_str = "parent_str"
      subclass_inst.save!

      expect(subclass_inst.str).to eq("foo")
      expect(subclass_inst.int_array).to eq([1,2,3])
      expect(subclass_inst.parent_str).to eq("parent_str")

      subclass_inst.reload

      expect(subclass_inst.str).to eq("foo")
      expect(subclass_inst.int_array).to eq([1,2,3])
      expect(subclass_inst.parent_str).to eq("parent_str")
    end
  end
end

