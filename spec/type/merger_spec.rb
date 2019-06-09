require 'spec_helper'

RSpec.describe AttrJson::Type::Merger do
  let(:klass) do
    TestRecord = Class.new(ActiveRecord::Base) do
      include AttrJson::Record
      self.table_name = "products"

      attr_json :foo, :integer, default: 1
      attr_json :bar, :string
    end
  end
  let(:instance) { klass.new }

  it 'works for the simplest case' do
    instance.bar = 2
    instance.save
    expect(instance.foo).to eq 1
    expect(instance.bar).to eq '2'

    instance.foo = 9
    instance.save
    expect(instance.foo).to eq 9
    expect(instance.json_attributes).to eq({ 'foo' => 9, 'bar' => '2'})

    instance.json_attributes = { a: 1, b: 2 }
    instance.save
    # expect(instance.json_attributes).to eq({ 'a' => 1, 'b' => '2', 'foo'=>9, 'bar'=>'2' })
    expect(instance.json_attributes).to eq({ 'a' => 1, 'b' => 2, 'foo' => 1})
  end

  it 'works for other_attributes' do
    instance.other_attributes = { a: 1, b: 2}
    instance.save
    expect(instance.other_attributes).to eq({ "a" => 1, "b" => 2})

    instance.other_attributes = { d: 1, e: 2}
    instance.save
    expect(instance.other_attributes).to eq({ "d" => 1, "e" => 2})
  end
end
