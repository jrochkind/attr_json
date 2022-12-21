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
      after_find do
        self.class.attr_json_registry.attribute_names.each do |attr_name|
          begin
            value = public_send(attr_name)
            if value
              write_attribute(attr_name, value)
              clear_attribute_change(attr_name)
            end
          rescue AttrJson::Type::Model::BadCast, AttrJson::Type::PolymorphicModel::TypeError => e
            # There was bad data in the DB, we're just going to skip the Rails attribute sync.
            # Should we log?
          end
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
      # @option options [Boolean] :validate (true) Create an ActiveRecord::Validations::AssociatedValidator so
      #   validation errors on the attributes post up to self.
      #
      def attr_json(name, type, **options)
        options = {
          validate: true,
          container_attribute: self.attr_json_config.default_container_attribute,
          accepts_nested_attributes: self.attr_json_config.default_accepts_nested_attributes
        }.merge!(options)
        options.assert_valid_keys(AttributeDefinition::VALID_OPTIONS + [:validate, :accepts_nested_attributes])
        container_attribute = options[:container_attribute]

        # TODO arg check container_attribute make sure it exists. Hard cause
        # schema isn't loaded yet when class def is loaded. Maybe not.

        # Want to lazily add an attribute cover to the json container attribute,
        # only if it hasn't already been done. WARNING we are using internal
        # Rails API here, but only way to do this lazily, which I thought was
        # worth it. On the other hand, I think .attribute is idempotent, maybe we don't need it...
        #
        # We set default to empty hash, because that 'tricks' AR into knowing any
        # application of defaults is a change that needs to be saved.
        unless attributes_to_define_after_schema_loads[container_attribute.to_s] &&
               attributes_to_define_after_schema_loads[container_attribute.to_s].first.is_a?(AttrJson::Type::ContainerAttribute) &&
               attributes_to_define_after_schema_loads[container_attribute.to_s].first.model == self
           # If this is already defined, but was for superclass, we need to define it again for
           # this class.
           attribute container_attribute.to_sym, AttrJson::Type::ContainerAttribute.new(self, container_attribute), default: -> { {} }
        end

        self.attr_json_registry = attr_json_registry.with(
          AttributeDefinition.new(name.to_sym, type, options.except(:validate, :accepts_nested_attributes))
        )

        # By default, automatically validate nested models
        if type.kind_of?(AttrJson::Type::Model) && options[:validate]
          self.validates_with ActiveRecord::Validations::AssociatedValidator, attributes: [name.to_sym]
        end

        # Register as a Rails attribute
        attr_json_definition = attr_json_registry[name]
        attribute_args = attr_json_definition.has_default? ? { default: attr_json_definition.default_argument } : {}
        self.attribute name.to_sym, attr_json_definition.type, **attribute_args

        _attr_jsons_module.module_eval do
          # For getter and setter, we used to use read_store_attribute/write_store_attribute
          # copied from Rails store_accessor implementation.
          # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96
          #
          # But in fact just getting/setting in the hash provided to us by ActiveRecord json type
          # container works BETTER for dirty tracking. We had a test that only passed doing it
          # this simple way.

          define_method("#{name}=") do |value|
            super(value) if defined?(super)
            attribute_def = self.class.attr_json_registry.fetch(name.to_sym)
            public_send(attribute_def.container_attribute)[attribute_def.store_key] = attribute_def.cast(value)
          end

          define_method("#{name}") do
            attribute_def = self.class.attr_json_registry.fetch(name.to_sym)
            public_send(attribute_def.container_attribute)[attribute_def.store_key]
          end
        end

        # Default attr_json_accepts_nested_attributes_for values
        if options[:accepts_nested_attributes]
          options = options[:accepts_nested_attributes] == true ? {} : options[:accepts_nested_attributes]
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
