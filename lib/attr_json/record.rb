# frozen_string_literal: true

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

      # Ensure that rails attributes tracker knows about values we just fetched
      after_initialize do
        attr_json_sync_to_rails_attributes
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
      self.class.attr_json_registry.definitions.group_by(&:container_attribute).each_pair do |container_attribute, definitions|
        begin
          # column may have eg been left out of an explicit 'select'
          next unless has_attribute?(container_attribute)

          container_value    = public_send(container_attribute)

          # isn't expected to be possible to be nil rather than empty hash, but
          # if it is from some edge case, well, we don't have values to sync, fine
          next if container_value.nil?

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
      end
    end

    class_methods do
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
            super(value) # should write to rails attribute

            # write to container hash, with value read from attribute to try to keep objects
            # sync'd to exact same object in rails attribute and container hash.
            attribute_def = self.class.attr_json_registry.fetch(name.to_sym)
            public_send(attribute_def.container_attribute)[attribute_def.store_key] = read_attribute(name)
          end

          define_method("#{name}") do
            # read from container hash -- we consider that the canonical location.
            attribute_def = self.class.attr_json_registry.fetch(name.to_sym)
            public_send(attribute_def.container_attribute)[attribute_def.store_key]
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
