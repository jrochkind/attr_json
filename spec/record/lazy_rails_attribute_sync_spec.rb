# A record loaded from the db syncs its json attributes to rails attributes
# only when needed, instead of all of them on load. Nothing a caller can
# observe should depend on that.
RSpec.describe "lazy sync to rails attributes" do
  # classes are named, as #becomes and Marshal need
  let(:model_class) do
    stub_const("LazySyncModel", Class.new do
      include AttrJson::Model

      attr_json :str, :string
    end)
  end

  let(:declarations) do
    model_class_type = model_class.to_type

    lambda do |klass|
      klass.table_name = "products"
      klass.attr_json :str, :string, default: "default"
      klass.attr_json :int, :integer, default: 0
      klass.attr_json :bool, :boolean, default: true
      klass.attr_json :date, :date
      klass.attr_json :hash_value, :json
      klass.attr_json :str_array, :string, array: true
      klass.attr_json :embedded, model_class_type, default: { str: "default" }
      klass.attr_json :other_str, :string, default: "default", container_attribute: :other_attributes
    end
  end

  let(:lazy_class) do
    declarations = self.declarations

    stub_const("LazySyncProduct", Class.new(ActiveRecord::Base) do
      include AttrJson::Record

      declarations.call(self)
    end)
  end

  # Syncs everything on load, as attr_json did before the sync became lazy.
  let(:eager_class) do
    stub_const("EagerSyncProduct", Class.new(lazy_class) do
      def self.attr_json_lazy_sync?
        false
      end
    end)
  end

  # What a record of either class above becomes: a class other than its own,
  # as Rails may treat becoming its own class differently.
  before do
    declarations = self.declarations

    stub_const("BecomeTargetProduct", Class.new(ActiveRecord::Base) do
      include AttrJson::Record

      declarations.call(self)
    end)

    stub_const("EagerBecomeTargetProduct", Class.new(BecomeTargetProduct) do
      def self.attr_json_lazy_sync?
        false
      end
    end)
  end

  # A row where every stored value differs from its default, so a rails
  # attribute that was never synced reads differently from one that was.
  def create_row
    id = lazy_class.create!(string_type: "column").id
    lazy_class.where(id: id).update_all([
      "json_attributes = ?::jsonb, other_attributes = ?::jsonb",
      {
        str: "stored", int: 7, bool: false, date: "2020-02-02", hash_value: { "a" => 1 },
        str_array: ["one"], embedded: { str: "stored" }
      }.to_json,
      { other_str: "stored" }.to_json
    ])
    id
  end

  def stored(id)
    lazy_class.where(id: id).pluck(:string_type, :json_attributes, :other_attributes).first
  end

  def count_updates
    count = 0
    counter = ->(*, payload) { count += 1 if payload[:sql].start_with?("UPDATE") }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  # Each scenario returns what a caller could observe. It is run on a record
  # loaded by the eager class and on one loaded by the lazy class.
  scenarios = {
    "an untouched record has no changes" => ->(record) {
      [record.changed?, record.changes, record.has_changes_to_save?, record.changed_attribute_names_to_save]
    },
    "getters" => ->(record) {
      [record.str, record.int, record.bool, record.date, record.hash_value, record.str_array, record.embedded, record.other_str]
    },
    "predicate methods" => ->(record) { [record.str?, record.bool?, record.int?] },
    "read_attribute and []" => ->(record) {
      [record.read_attribute(:str), record[:int], record["bool"], record.read_attribute("other_str"), record[:embedded]]
    },
    "attribute_present?" => ->(record) { [record.attribute_present?(:str), record.attribute_present?(:date), record.has_attribute?(:int)] },
    "pretty_print" => ->(record) {
      require "pp"
      record.pretty_inspect.gsub(/#<[^ \n]+/, "").sub(/id: \d+/, "")
    },
    "attributes" => ->(record) { record.attributes.except("id") },
    "inspect" => ->(record) { [record.attribute_for_inspect(:str), record.inspect.gsub(/#<[^ ]+/, "").sub(/id: \d+/, "")] },
    "read_attribute_before_type_cast" => ->(record) {
      [record.read_attribute_before_type_cast(:str), record.int_before_type_cast, record.embedded_before_type_cast]
    },
    "came_from_user?" => ->(record) { [record.str_came_from_user?, record.int_came_from_user?] },
    "for_database" => ->(record) { record.respond_to?(:str_for_database) && [record.str_for_database, record.embedded_for_database] },
    "will_change!" => ->(record) {
      record.str_will_change!
      record.str << "more"
      record.int_will_change!
      [record.changes, record.str_was, record.int_was]
    },
    "every dirty tracking method, on an untouched record" => ->(record) {
      [
        record.changed, record.changed_attributes, record.changes_to_save, record.attributes_in_database,
        record.str_changed?, record.attribute_changed?(:int), record.str_change, record.embedded_change,
        record.will_save_change_to_str?, record.str_change_to_be_saved, record.attribute_changed_in_place?(:str),
        record.saved_changes, record.str_previously_changed?, record.str_previous_change, record.saved_change_to_int?,
        record.str_before_last_save
      ]
    },
    "every dirty tracking method, after a write and an in place mutation" => ->(record) {
      record.int = 8
      record.str << "more"
      record.embedded.str = "new"
      [
        record.changed.sort, record.changed_attributes, record.changes_to_save, record.attributes_in_database,
        record.str_changed?, record.attribute_changed?(:int, from: 7, to: 8), record.bool_changed?, record.str_change,
        record.will_save_change_to_str?, record.int_change_to_be_saved, record.attribute_changed_in_place?(:str),
        record.other_str_was, record.bool_in_database, record.has_changes_to_save?
      ]
    },
    "restore and clear a single attribute" => ->(record) {
      record.str = "new"
      record.int = 8
      record.restore_str!
      record.clear_attribute_changes([:int])
      record.clear_attribute_changes(["bool"])
      [record.changes, record.str, record.read_attribute(:int), record.bool_was]
    },
    "attributes_before_type_cast" => ->(record) { record.attributes_before_type_cast.slice("str", "int", "bool", "other_str") },
    "read_attribute_for_database" => ->(record) {
      record.respond_to?(:read_attribute_for_database) && record.read_attribute_for_database(:str)
    },
    "attributes_for_database" => ->(record) {
      record.respond_to?(:attributes_for_database) && record.attributes_for_database.slice("str", "int", "bool", "other_str")
    },
    "serializable_hash and as_json" => ->(record) { [record.serializable_hash.except("id"), record.as_json.except("id")] },
    "value in database before any write" => ->(record) {
      [record.str_was, record.int_in_database, record.attribute_was(:bool), record.embedded_was, record.attribute_in_database("other_str")]
    },
    "a write" => ->(record) {
      record.str = "new"
      record.other_str = "new"
      [record.changed.sort, record.str_changed?, record.str_was, record.changes, record.attributes_in_database]
    },
    "a write through write_attribute" => ->(record) {
      record.write_attribute(:str, "new")
      record[:int] = 8
      [record.str_changed?, record.str_was, record.changes]
    },
    "a write of the stored value" => ->(record) {
      record.str = "stored"
      record.bool = false
      record.embedded = { str: "stored" }
      [record.changed?, record.changes]
    },
    "assign_attributes" => ->(record) {
      record.assign_attributes(str: "new", int: 7)
      [record.changes, record.int_changed?]
    },
    "a write, saved" => ->(record) {
      record.int = 8
      record.save!
      [record.saved_change_to_int?, record.saved_changes, record.int_before_last_save, record.changed?, record.attributes.except("id")]
    },
    "update!" => ->(record) {
      record.update!(str: "new", other_str: "new")
      [record.saved_changes, record.changed?]
    },
    "a save with no changes" => ->(record) {
      record.save!
      [record.saved_changes, record.attributes.except("id")]
    },
    "a string mutated in place" => ->(record) {
      record.str << "more"
      before = [record.changed?, record.str_changed?, record.str_was, record.changes]
      record.save!
      [before, record.saved_changes]
    },
    "a hash mutated in place" => ->(record) {
      record.hash_value["b"] = 2
      before = [record.changed?, record.hash_value_changed?, record.hash_value_was, record.changes]
      record.save!
      [before, record.saved_changes]
    },
    "an array mutated in place" => ->(record) {
      record.str_array << "two"
      before = [record.changed?, record.str_array_changed?, record.str_array_was, record.changes]
      record.save!
      [before, record.saved_changes]
    },
    "a nested model mutated in place" => ->(record) {
      record.embedded.str = "new"
      before = [record.changed?, record.embedded_changed?, record.embedded_was, record.changes]
      record.save!
      [before, record.saved_changes]
    },
    "two values mutated in place, after other reads" => ->(record) {
      record.int
      record.str << "more"
      record.attributes
      record.other_str << "more"
      [record.changes, record.str_was, record.other_str_was]
    },
    "mutated in place, then written" => ->(record) {
      record.str << "more"
      record.str = "new"
      record.int = 8
      [record.changes, record.str_was]
    },
    "the same object in rails attribute and container" => ->(record) {
      [
        record.str.equal?(record.read_attribute(:str)),
        record.read_attribute(:embedded).equal?(record.json_attributes["embedded"]),
        record.attributes["str_array"].equal?(record.str_array)
      ]
    },
    "a value written straight into the container" => ->(record) {
      record.json_attributes["str"] = "direct"
      before = [record.changed?, record.str, record.str_changed?]
      record.save!
      [before, record.read_attribute(:str)]
    },
    "a value written straight into the container, before anything else" => ->(record) {
      record.json_attributes["str"] = "direct"
      [record.str_was, record.str_changed?, record.changes, record.read_attribute(:str), record.str]
    },
    "a value mutated in place through the container" => ->(record) {
      record.json_attributes["str_array"] << "two"
      record[:other_attributes]["other_str"] << "more"
      [record.str_array_changed?, record.str_array_was, record.other_str_changed?, record.changes]
    },
    "a container replaced" => ->(record) {
      record.json_attributes = { "str" => "replaced", "int" => 9 }
      before = [record.str_was, record.int_in_database, record.changes, record.str, record.read_attribute(:str)]
      record.save!
      [before, record.saved_changes, record.attributes.except("id")]
    },
    "a container replaced through assign_attributes" => ->(record) {
      record.assign_attributes(other_attributes: { "other_str" => "replaced" }, int: 9)
      [record.other_str_was, record.changes, record.other_str]
    },
    "restore_attributes" => ->(record) {
      record.str = "new"
      record.int = 8
      record.restore_attributes
      [record.str, record.int, record.read_attribute(:str), record.changed?]
    },
    "clear_changes_information" => ->(record) {
      record.str = "new"
      record.clear_changes_information
      [record.changes, record.str, record.read_attribute(:int), record.int_was]
    },
    "a rolled back transaction that saved the record" => ->(record) {
      record.class.transaction do
        record.update!(string_type: "new")
        raise ActiveRecord::Rollback
      end
      [record.changed, record.str_was, record.read_attribute(:int), record.attributes.except("id")]
    },
    "a rolled back transaction that saved the record after an in place mutation" => ->(record) {
      record.class.transaction do
        record.str << "more"
        record.save!
        record.embedded
        raise ActiveRecord::Rollback
      end
      [record.changed.sort, record.str_was, record.read_attribute(:str), record.read_attribute(:int), record.embedded_was]
    },
    "a rolled back transaction that touched the record" => ->(record) {
      record.class.transaction do
        record.touch(:datetime_type)
        record.touch(:datetime_type, time: Time.utc(2020, 2, 2))
        record.str
        record.read_attribute(:int)
        raise ActiveRecord::Rollback
      end
      [record.changed, record.str_was, record.read_attribute(:int), record.attributes.except("id"), record.embedded_was]
    },
    "a rolled back transaction that saved and reloaded the record" => ->(record) {
      record.str = "new"
      record.class.transaction do
        record.save!
        record.reload
        record.embedded
        raise ActiveRecord::Rollback
      end
      record.int
      record.str
      [record.changes, record.str_was, record.read_attribute(:int), record.attributes.except("id")]
    },
    "a rolled back transaction that destroyed the record" => ->(record) {
      record.class.transaction do
        record.destroy
        raise ActiveRecord::Rollback
      end
      record.str << "more"
      [record.changes, record.read_attribute(:int), record.frozen?, record.destroyed?]
    },
    "a nested transaction rolled back" => ->(record) {
      record.class.transaction do
        record.update!(int: 8)
        record.class.transaction(requires_new: true) do
          record.update!(str: "inner")
          raise ActiveRecord::Rollback
        end
      end
      [record.changes, record.str_was, record.int_was, record.attributes.except("id")]
    },
    "increment and toggle" => ->(record) {
      record.increment(:int)
      record.toggle(:bool)
      [record.changes, record.read_attribute(:int), record[:bool]]
    },
    "reload of an untouched record" => ->(record) {
      record.class.where(id: record.id).update_all(%q{json_attributes = jsonb_set(json_attributes, '{str}', '"fromdb"')})
      record.reload
      record.str << "more"
      [record.str_was, record.changes, record.read_attribute(:int)]
    },
    "reload of a record that was written" => ->(record) {
      record.update!(int: 8)
      record.str
      record.class.where(id: record.id).update_all(%q{json_attributes = jsonb_set(json_attributes, '{str}', '"fromdb"')})
      record.reload
      [record.str, record.read_attribute(:str), record.str_was, record.changed?, record.attributes.except("id")]
    },
    "dup" => ->(record) {
      copy = record.dup
      [copy.new_record?, copy.changes, copy.attributes, copy.str, copy.embedded, record.changed?]
    },
    "dup after an in place mutation" => ->(record) {
      record.str << "more"
      copy = record.dup
      copy.str << "evenmore"
      [copy.changes, copy.str, record.str, record.changes]
    },
    "clone" => ->(record) {
      copy = record.clone
      copy.str << "more"
      [copy.changes, record.changes, copy.read_attribute(:int)]
    },
    "becomes" => ->(record) {
      other = record.becomes(BecomeTargetProduct)
      [other.str_was, other.read_attribute(:int), other.changed?, other.attributes.except("id")]
    },
    "becomes, after an in place mutation" => ->(record) {
      record.str << "more"
      other = record.becomes(BecomeTargetProduct)
      before = [other.changed?, record.changed?, other.changes, record.changes]
      [before, other.str, other.str_was, record.str_changed?]
    },
    "becomes its own class" => ->(record) {
      record.str << "more"
      record.int = 8
      other = record.becomes(record.class)
      [other.changes, record.changes, other.str, other.read_attribute(:int), other.str_was]
    },
    "becomes a class that syncs on load" => ->(record) {
      record.str = "new"
      other = record.becomes(EagerBecomeTargetProduct)
      [other.changes, record.changes, other.str, other.read_attribute(:int)]
    },
    "to_yaml" => ->(record) {
      require "yaml"
      record.to_yaml.gsub(/(Eager|Lazy)SyncProduct/, "Product").sub(/name: id\n\s+value_before_type_cast: \d+/, "name: id")
    },
    "a row without the keys that have defaults: dirty tracking" => ->(record) {
      record.class.where(id: record.id).update_all("json_attributes = '{}', other_attributes = '{}'")
      loaded = record.class.find(record.id)
      [
        loaded.changed?, loaded.changed.sort, loaded.changes, loaded.changed_attributes, loaded.attributes_in_database,
        loaded.has_changes_to_save?, loaded.changes_to_save, loaded.changed_attribute_names_to_save.sort
      ]
    },
    "a row without the keys that have defaults: dirty tracking of the container" => ->(record) {
      record.class.where(id: record.id).update_all("json_attributes = '{}'")
      [
        record.class.find(record.id).json_attributes_changed?,
        record.class.find(record.id).attribute_changed?(:json_attributes),
        record.class.find(record.id).will_save_change_to_json_attributes?,
        record.class.find(record.id).json_attributes_change,
        record.class.find(record.id).json_attributes_change_to_be_saved,
        record.class.find(record.id).json_attributes_was,
        record.class.find(record.id).str_changed?
      ]
    },
    "a row without the keys that have defaults: saved if changed" => ->(record) {
      record.class.where(id: record.id).update_all("json_attributes = '{}'")
      loaded = record.class.find(record.id)
      loaded.save! if loaded.changed?
      [loaded.saved_changes, loaded.str]
    },
    "a row without the keys that have defaults: saved" => ->(record) {
      record.class.where(id: record.id).update_all("json_attributes = '{}'")
      loaded = record.class.find(record.id)
      loaded.save!
      [loaded.saved_changes, loaded.changed?]
    },
    "a row without the keys that have defaults: touched" => ->(record) {
      record.class.where(id: record.id).update_all("json_attributes = '{}'")
      loaded = record.class.find(record.id)
      loaded.touch(:datetime_type)
      [loaded.changed?, loaded.changes.keys]
    },
    "YAML round trip" => ->(record) {
      require "yaml"
      yaml = record.to_yaml
      copy = YAML.respond_to?(:unsafe_load) ? YAML.unsafe_load(yaml) : YAML.load(yaml)
      [copy.read_attribute(:str), copy.int, copy.changes, copy.embedded]
    },
    "reload in a rolled back transaction, then an in place mutation" => ->(record) {
      record.class.transaction do
        record.reload
        raise ActiveRecord::Rollback
      end
      record.str << "more"
      record.embedded.str = "new"
      [record.str_changed?, record.embedded_changed?, record.str.equal?(record.read_attribute(:str)), record.changes]
    },
    "with_lock in a rolled back transaction, then an in place mutation" => ->(record) {
      record.class.transaction do
        record.with_lock { record.int }
        raise ActiveRecord::Rollback
      end
      record.str << "more"
      [record.str_changed?, record.str.equal?(record.read_attribute(:str)), record.changes]
    },
    "touch and reload in a rolled back transaction, then an in place mutation" => ->(record) {
      record.class.transaction do
        record.touch(:datetime_type)
        record.reload
        raise ActiveRecord::Rollback
      end
      record.str << "more"
      record.embedded.str = "new"
      [record.str_changed?, record.embedded_changed?, record.str.equal?(record.read_attribute(:str)), record.changes.keys.sort]
    },
    "becomes, with unsaved changes" => ->(record) {
      record.str = "new"
      record.embedded.str = "new"
      other = record.becomes(BecomeTargetProduct)
      read = [other.str, other.read_attribute(:int), other.embedded, other.attributes.except("id")]
      [read, other.changes, record.changes, other.str_was]
    },
    "destroy" => ->(record) {
      record.destroy
      [record.str, record.embedded, record.read_attribute(:str), record.attributes.except("id"), record.changed?, record.frozen?]
    },
    "delete" => ->(record) {
      record.delete
      [record.str, record.read_attribute(:str), record.attributes.except("id"), record.changed?, record.frozen?]
    },
    "freeze" => ->(record) {
      record.freeze
      [record.str, record.str_array, record[:int], record.changed?]
    },
    "Marshal round trip" => ->(record) {
      record.int
      record.str << "more"
      copy = Marshal.load(Marshal.dump(record))
      [copy.changes, copy.str, copy.read_attribute(:int), copy.attributes.except("id")]
    },
    "a record loaded without the container columns" => ->(record) {
      partial = record.class.select(:id, :string_type).find(record.id)
      partial.string_type = "new"
      [partial.changes, partial.attributes.except("id")]
    },
    "a record loaded with only one container column" => ->(record) {
      partial = record.class.select(:id, :other_attributes).find(record.id)
      partial.other_str << "more"
      [partial.changes, partial.other_str_was]
    }
  }

  scenarios.each do |description, scenario|
    it "does not change: #{description}" do
      eager = lazy = nil
      eager_id, lazy_id = create_row, create_row

      eager_updates = count_updates { eager = scenario.call(eager_class.find(eager_id)) }
      lazy_updates = count_updates { lazy = scenario.call(lazy_class.find(lazy_id)) }

      expect(lazy).to eq(eager)
      expect(stored(lazy_id)).to eq(stored(eager_id))
      expect(lazy_updates).to eq(eager_updates)
    end
  end

  describe "a class with alias_attribute for a json attribute" do
    let(:aliasing_class) do
      stub_const("AliasingProduct", Class.new(lazy_class) do
        alias_attribute :title, :str
      end)
    end

    it "reads the stored value through the alias" do
      record = aliasing_class.find(create_row)

      expect(record.title).to eq "stored"
      expect(record.title_was).to eq "stored"
      expect(record.title_changed?).to be false
    end

    it "reads and writes through the rails attribute methods with the alias" do
      expect(aliasing_class.find(create_row).read_attribute(:title)).to eq "stored"
      expect(aliasing_class.find(create_row)[:title]).to eq "stored"

      record = aliasing_class.find(create_row)
      record.title = "new"
      expect(record.changes).to include("str" => ["stored", "new"])
    end

    it "is noticed when declared after the class was used" do
      late_class = stub_const("LateAliasingProduct", Class.new(lazy_class))
      id = create_row
      late_class.find(id)
      late_class.alias_attribute :title, :str

      expect(late_class.find(id).title).to eq "stored"
    end

    it "does not stop its superclass from syncing lazily" do
      aliasing_class
      expect(lazy_class.attr_json_lazy_sync?).to be true
      expect(aliasing_class.attr_json_lazy_sync?).to be false
    end
  end

  describe "when the sync happens" do
    let!(:record) { lazy_class.find(create_row) }

    # rails attributes that still hold their default were not synced
    def unsynced_attributes(record)
      record.instance_variable_get(:@attributes).to_hash.slice(
        "str", "int", "bool", "str_array", "embedded", "other_str"
      ).select { |name, value| value == lazy_class.new.attributes[name] }.keys
    end

    it "is not on load" do
      expect(model_class).not_to receive(:new)
      lazy_class.find(record.id)
    end

    it "is not on reading a column" do
      record.string_type
      expect(unsynced_attributes(record)).to eq(%w[str int bool str_array embedded other_str])
    end

    it "is for that attribute only on reading it" do
      record.str
      record.embedded
      record.bool
      expect(unsynced_attributes(record)).to eq(%w[int str_array other_str])
    end

    it "is for that attribute only on a write" do
      record.int = 8
      expect(unsynced_attributes(record)).to eq(%w[str bool str_array embedded other_str])
    end

    it "is not on a use of dirty tracking for the whole record" do
      expect(record.changed?).to be false
      expect(record.changes).to eq({})
      expect(unsynced_attributes(record)).to eq(%w[str int bool str_array embedded other_str])
    end

    it "is for all attributes on reading them all" do
      record.attributes
      expect(unsynced_attributes(record)).to eq([])
    end

    it "is for all attributes before a save" do
      record.string_type = "new"
      record.save!
      expect(unsynced_attributes(record)).to eq([])
    end

    it "is right away for a new record" do
      new_record = lazy_class.new(int: 7)
      expect(new_record.instance_variable_get(:@attributes).to_hash).to include("int" => 7, "str" => "default")
      expect(new_record.changes).to include("int" => [0, 7])
    end
  end
end
