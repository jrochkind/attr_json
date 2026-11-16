# frozen_string_literal: true

require 'set'
require 'attr_json/attribute_definition'
require 'attr_json/attribute_definition/registry'
require 'attr_json/type/container_attribute'

module AttrJson
  # The mix-in to provide AttrJson support to ActiveRecord::Base models.
  # We call it `Record` instead of `ActiveRecord` to avoid confusing namespace
  # shadowing errors, sorry!
  #
  # @example
  #       class SomeModel < ActiveRecord::Base
  #         include AttrJson::Record
  #
  #         attr_json :a_number, :integer
  #       end
  #
  module Record
    extend ActiveSupport::Concern

    included do
      unless self <= ActiveRecord::Base
        raise TypeError, "AttrJson::Record can only be used with an ActiveRecord::Base model. #{self} does not appear to be one. Are you looking for ::AttrJson::Model?"
      end

      class_attribute :attr_json_registry, instance_accessor: false
      self.attr_json_registry = AttrJson::AttributeDefinition::Registry.new

      # Ensure that rails attributes tracker knows about values we just fetched.
      #
      # A record loaded from the db syncs lazily instead, see below. (A `dup` is
      # also persisted? here, but has the instance variable from its source.)
      after_initialize do
        if persisted? && !instance_variable_defined?(:@attr_json_lazily_synced) && self.class.attr_json_lazy_sync?
          @attr_json_lazily_synced = Set.new
        else
          attr_json_sync_to_rails_attributes
        end
      end

      # A save replaces the rails attributes with new objects, and a transaction
      # rollback brings the old ones back: they have to be synced by now.
      before_save do
        attr_json_sync_if_unsynced
      end

      # After a safe, rails attribute dirty tracking ends up re-creating
      # new objects for attribute values, so we need to sync again
      # so mutation effects both.
      after_save do
        attr_json_sync_to_rails_attributes
      end
    end

    # Sync all values FROM the json_attributes json column TO rails attributes
    #
    # If values have for some reason gotten out of sync this will make them the
    # identical objects again, with the container hash value being the source.
    #
    # In some cases, the values may already be equivalent but different objects --
    # This is meant to ensure they are the _same object_ in both places, so
    # mutation of mutable object will effect both places, for instance for dirty
    # tracking.
    def attr_json_sync_to_rails_attributes
      @attr_json_lazily_synced = nil
      attr_json_sync_definitions(self.class.attr_json_registry.definitions)
    end

    # A record loaded from the db syncs lazily: each attribute when first needed,
    # by our getter and setter or by the methods below, which are the other ways
    # to reach the value of a rails attribute. Dirty tracking of the whole record
    # needs no sync, as an attribute nobody touched has no changes.

    # Some are not in every Rails version we support. (Asking ActiveRecord::Base
    # here would load it too early.)
    before_type_cast = ActiveRecord::AttributeMethods::BeforeTypeCast

    one_attribute_methods = %i[
      read_attribute read_attribute_before_type_cast attribute_present? attribute_for_inspect
      attribute_was attribute_in_database attribute_changed_in_place? attribute_change_to_be_saved
    ]
    one_attribute_methods << :read_attribute_for_database if before_type_cast.method_defined?(:read_attribute_for_database)

    one_attribute_methods.each do |method_name|
      define_method(method_name) do |attr_name, &block|
        attr_json_sync_attribute_if_unsynced(attr_name)
        super(attr_name, &block)
      end
    end

    def write_attribute(attr_name, value)
      attr_json_sync_attribute_if_unsynced(attr_name)
      super
    end

    %i[attribute_changed? will_save_change_to_attribute?].each do |method_name|
      define_method(method_name) do |attr_name, **options|
        attr_json_sync_attribute_if_unsynced(attr_name)
        super(attr_name, **options)
      end
    end

    # Rails only sees a change in a container it has read, such as defaults
    # for keys the db did not have.
    %i[
      changed? changed changes changed_attributes attributes_in_database
      has_changes_to_save? changes_to_save changed_attribute_names_to_save
    ].each do |method_name|
      define_method(method_name) do
        attr_json_read_containers if @attr_json_lazily_synced
        super()
      end
    end

    # These read all rails attributes (attributes, pretty_print, encode_with), copy or share
    # them (dup, clone, becomes), make them unwritable (freeze, destroy, delete),
    # or like a save replace them (touch).
    all_attributes_methods = %i[attributes attributes_before_type_cast dup freeze destroy delete]
    all_attributes_methods << :attributes_for_database if before_type_cast.method_defined?(:attributes_for_database)
    # Later Rails #inspect uses #attribute_for_inspect, and with #inspect
    # overridden would pretty_print differently.
    all_attributes_methods << :inspect if ActiveRecord.version < Gem::Version.new("6.1")

    all_attributes_methods.each do |method_name|
      define_method(method_name) do
        attr_json_sync_if_unsynced
        super()
      end
    end

    def pretty_print(pp)
      attr_json_sync_if_unsynced
      super
    end

    def encode_with(coder)
      attr_json_sync_if_unsynced
      super
    end

    def clone(**options)
      attr_json_sync_if_unsynced
      super
    end

    # Later Rails runs after_initialize on the record we become when it has
    # our rails attributes already. It then believes it was just loaded, where
    # it used to sync.
    def becomes(klass)
      attr_json_sync_if_unsynced
      super.tap do |became|
        became.attr_json_sync_to_rails_attributes if became.instance_variable_get(:@attr_json_lazily_synced)
      end
    end

    def touch(*names, **options)
      attr_json_sync_if_unsynced
      super
    end

    # Not lazily: a transaction rollback can bring back the rails attributes
    # from before the reload, which are synced.
    def reload(*)
      super.tap { attr_json_sync_to_rails_attributes }
    end

    private

    # @attr_json_lazily_synced is nil, unless this record syncs lazily and is
    # not done: then it has the names of the attributes synced so far.

    def attr_json_sync_attribute_if_unsynced(attr_name)
      synced = @attr_json_lazily_synced
      return if synced.nil? || !attr_name.respond_to?(:to_sym)

      registry = self.class.attr_json_registry
      definition = registry[attr_name]
      if definition.nil?
        # someone with the container can change values before we synced them
        attr_json_sync_if_unsynced if registry.container_attribute?(attr_name)
        return
      end
      return if synced.include?(definition.name)

      attr_json_without_lazy_sync do
        attr_json_sync_from_container(definition.container_attribute, [definition])
      end
      synced << definition.name
      @attr_json_lazily_synced = nil if synced.size == registry.definitions.size
    end

    def attr_json_sync_if_unsynced
      synced = @attr_json_lazily_synced
      return if synced.nil?

      attr_json_without_lazy_sync do
        attr_json_sync_definitions(self.class.attr_json_registry.definitions.reject { |d| synced.include?(d.name) })
      end
      @attr_json_lazily_synced = nil
    end

    # The sync itself, and our getters and setters, use rails attribute methods
    # that would otherwise start a sync.
    def attr_json_without_lazy_sync
      synced, @attr_json_lazily_synced = @attr_json_lazily_synced, nil
      yield
    ensure
      @attr_json_lazily_synced = synced
    end

    def attr_json_read_containers
      self.class.attr_json_registry.container_attributes.each do |container_attribute|
        attr_json_container(container_attribute) if has_attribute?(container_attribute)
      end
    end

    def attr_json_container(container_attribute)
      return public_send(container_attribute) if @attr_json_lazily_synced.nil?

      attr_json_without_lazy_sync { public_send(container_attribute) }
    end

    def attr_json_sync_definitions(definitions)
      definitions.group_by(&:container_attribute).each_pair do |container_attribute, container_definitions|
        attr_json_sync_from_container(container_attribute, container_definitions)
      end
    end

    def attr_json_sync_from_container(container_attribute, definitions)
      # column may have eg been left out of an explicit 'select'
      return unless has_attribute?(container_attribute)

      container_value    = attr_json_container(container_attribute)

      # isn't expected to be possible to be nil rather than empty hash, but
      # if it is from some edge case, well, we don't have values to sync, fine
      return if container_value.nil?

      definitions.each do |attribute_def|
        attr_name     = attribute_def.name
        value         = container_value[attribute_def.store_key]

        unless value.nil?
          # TODO, can we just make this use the setter?
          write_attribute(attr_name, value)

          clear_attribute_change(attr_name) if persisted?

          # writing and clearning will result in a new object stored in
          # rails attributes, we want
          # to make sure the exact same object is in the json attribute,
          # so in-place mutation changes to it are reflected in both places.
          container_value[attribute_def.store_key] = read_attribute(attr_name)
        end
      end
    rescue AttrJson::Type::Model::BadCast, AttrJson::Type::PolymorphicModel::TypeError => e
      # There was bad data in the DB, we're just going to skip the Rails attribute sync.
      # Should we log?
    end

    class_methods do
      # A reader made by alias_attribute reads the rails attribute directly,
      # with nothing for us to override, so such a class syncs on load.
      def attr_json_lazy_sync?
        attribute_aliases.empty? ||
          attribute_aliases.each_value.none? { |name| attr_json_registry.has_attribute?(name) }
      end

      # Access or set class-wide json_attribute_config. Inherited by sub-classes,
      # but setting on sub-classes is unique to subclass. Similar to how
      # rails class_attribute's are used.
      #
      # @example access config
      #   SomeClass.attr_json_config
      #
      # @example set config variables
      #    class SomeClass < ActiveRecordBase
      #       include JsonAttribute::Record
      #
      #       attr_json_config(default_container_attribute: "some_column")
      #    end
      # TODO make Model match please.
      def attr_json_config(new_values = {})
        if new_values.present?
          # get one without new values, then merge new values into it, and
          # set it locally for this class.
          @attr_json_config = attr_json_config.merge(new_values)
        else
          if instance_variable_defined?("@attr_json_config")
            # we have a custom one for this class, return it.
            @attr_json_config
          elsif superclass.respond_to?(:attr_json_config)
            # return superclass without setting it locally, so changes in superclass
            # will continue effecting us.
            superclass.attr_json_config
          else
            # no superclass, no nothing, set it to blank one.
            @attr_json_config = Config.new(mode: :record)
          end
        end
      end


      # Registers an attr_json attribute, and a Rails attribute covering it.
      #
      # Type can be a symbol that will be looked up in `ActiveModel::Type.lookup`,
      # or an ActiveModel:::Type::Value).
      #
      # @param name [Symbol,String] name of attribute
      #
      # @param type [ActiveModel::Type::Value] An instance of an ActiveModel::Type::Value (or subclass)
      #
      # @option options [Boolean] :array (false) Make this attribute an array of given type.
      #    Array types default to an empty array. If you want to turn that off, you can add
      #    `default: AttrJson::AttributeDefinition::NO_DEFAULT_PROVIDED`
      #
      # @option options [Object] :default (nil) Default value, if a Proc object it will be #call'd
      #   for default.
      #
      # @option options [String,Symbol] :store_key (nil) Serialize to JSON using
      #   given store_key, rather than name as would be usual.
      #
      # @option options [Symbol,String] :container_attribute (attr_json_config.default_container_attribute, normally `json_attributes`) The real
      #   json(b) ActiveRecord attribute/column to serialize as a key in. Defaults to
      #  `attr_json_config.default_container_attribute`, which defaults to `:json_attributes`
      #
      # @option options [Boolean] :validate (true) validation errors on nested models in the attributes
      #   should post up to self similar to Rails ActiveRecord::Validations::AssociatedValidator on
      #   associated objects.
      #
      # @option options [Boolean,Hash] :accepts_nested_attributes. If true, equivalent
      #   of  writing `attr_json_accepts_nested_attributes :attribute_name`. If value is a hash,
      #   then same, but with hash as options to `attr_json_accepts_nested_attributes`.
      #   Default taken from `attr_json_config.default_accepts_nested_attributes`, for
      #   array or model types where it is applicable.
      #
      def attr_json(name, type, **options)
        options = {
          validate: true,
          container_attribute: self.attr_json_config.default_container_attribute,
        }.merge!(options)
        options.assert_valid_keys(AttributeDefinition::VALID_OPTIONS + [:validate, :accepts_nested_attributes])
        container_attribute = options[:container_attribute]


        # Make sure to "lazily" register attribute for *container* class if this is the first time
        # this container attribute hsa been encountered for this specific class. The registry
        # helps us keep track. Kinda messy, in future we may want a more explicit API
        # that does not require us to implicitly track first-time per-container.
        unless self.attr_json_registry.container_attribute_registered?(model: self, attribute_name: container_attribute.to_sym)
           attribute container_attribute.to_sym, AttrJson::Type::ContainerAttribute.new(self, container_attribute), default: -> { {} }
           self.attr_json_registry.register_container_attribute(model: self, attribute_name: container_attribute.to_sym)
        end

        self.attr_json_registry = attr_json_registry.with(
          AttributeDefinition.new(name.to_sym, type, options.except(:validate, :accepts_nested_attributes))
        )

        # By default, automatically validate nested models, allowing nils.
        if type.kind_of?(AttrJson::Type::Model) && options[:validate]
          # implementation adopted from:
          #   https://github.com/rails/rails/blob/v7.0.4.1/activerecord/lib/active_record/validations/associated.rb#L6-L10
          #
          # but had to customize to allow nils in an array through
          validates_each name.to_sym do |record, attr, value|
            if Array(value).reject { |element| element.nil? || element.valid? }.any?
              record.errors.add(attr, :invalid, value: value)
            end
          end
        end

        # Register as a Rails attribute
        attr_json_definition = attr_json_registry[name]
        attribute_args = attr_json_definition.has_default? ? { default: attr_json_definition.default_argument } : {}
        self.attribute name.to_sym, attr_json_definition.type, **attribute_args

        # For getter and setter, we consider the container has the "canonical" data location.
        # But setter also writes to rails attribute, and tries to keep them in sync with the
        # *same object*, so mutations happen to both places.
        #
        # This began roughly modelled on approach of Rail sstore_accessor implementation:
        # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96
        #
        # ...But wound up with lots of evolution to try to get dirty tracking working as well
        # as we could -- without a completely custom separate dirty tracking implementation
        # like store_accessor tries!
        _attr_jsons_module.module_eval do
          define_method("#{name}=") do |value|
            # rails dirty tracking needs the value from the db to compare to
            attr_json_sync_attribute_if_unsynced(name)

            super(value) # should write to rails attribute

            # write to container hash, with value read from attribute to try to keep objects
            # sync'd to exact same object in rails attribute and container hash.
            attribute_def = self.class.attr_json_registry.fetch(name.to_sym)
            attr_json_container(attribute_def.container_attribute)[attribute_def.store_key] = read_attribute(name)
          end

          define_method("#{name}") do
            # read from container hash -- we consider that the canonical location.
            attribute_def = self.class.attr_json_registry.fetch(name.to_sym)

            if @attr_json_lazily_synced
              attr_json_sync_attribute_if_unsynced(name)
              attr_json_container(attribute_def.container_attribute)[attribute_def.store_key]
            else
              public_send(attribute_def.container_attribute)[attribute_def.store_key]
            end
          end

          # rails methods for this attribute that we can't override for all attributes at once
          %w[_before_type_cast _for_database _came_from_user? _will_change!].each do |suffix|
            # Rails 6.0 has no `name_for_database`
            next if suffix == "_for_database" && ActiveRecord.version < Gem::Version.new("6.1")

            define_method("#{name}#{suffix}") do
              attr_json_sync_attribute_if_unsynced(name)
              super()
            end
          end

          # Someone with the container can change values in it, or replace it,
          # before we synced them.
          container_attribute = attr_json_definition.container_attribute
          unless method_defined?(container_attribute)
            define_method(container_attribute) do
              attr_json_sync_if_unsynced
              super()
            end

            define_method("#{container_attribute}=") do |value|
              attr_json_sync_if_unsynced
              super(value)
            end

            define_method("#{container_attribute}_change") do
              attr_json_sync_if_unsynced
              super()
            end
          end
        end

        accepts_nested_attributes = if options.has_key?(:accepts_nested_attributes)
          options[:accepts_nested_attributes]
        elsif attr_json_definition.single_model_type? || attr_json_definition.array_type?
          # use configured default only if we have a type appropriate for it!
          self.attr_json_config.default_accepts_nested_attributes
        else
          false
        end

        if accepts_nested_attributes
          options = accepts_nested_attributes == true ? {} : accepts_nested_attributes
          self.attr_json_accepts_nested_attributes_for name, **options
        end
      end

      private

      # Define an anonymous module and include it, so can still be easily
      # overridden by concrete class. Design cribbed from ActiveRecord::Store
      # https://github.com/rails/rails/blob/4590d7729e241cb7f66e018a2a9759cb3baa36e5/activerecord/lib/active_record/store.rb
      def _attr_jsons_module # :nodoc:
        @_attr_jsons_module ||= begin
          mod = Module.new
          include mod
          mod
        end
      end
    end
  end
end
