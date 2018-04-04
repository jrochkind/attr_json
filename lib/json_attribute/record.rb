require 'json_attribute/attribute_definition'
require 'json_attribute/attribute_definition/registry'
require 'json_attribute/type/container_attribute'

module JsonAttribute
  # The mix-in to provide JsonAttribute support to ActiveRecord::Base models.
  # We call it `Record` instead of `ActiveRecord` to avoid confusing namespace
  # shadowing errors, sorry!
  #
  #    class SomeModel < ActiveRecord::Base
  #      include JsonAttribute::Record
  #
  #      json_attribute :a_number, :integer
  #    end
  #
  module Record
    extend ActiveSupport::Concern

    included do
      unless self < ActiveRecord::Base
        raise TypeError, "JsonAttribute::Record can only be used with an ActiveRecord::Base model. #{self} does not appear to be one. Are you looking for ::JsonAttribute::Model?"
      end

      class_attribute :json_attributes_registry, instance_accessor: false
      self.json_attributes_registry = JsonAttribute::AttributeDefinition::Registry.new
    end


    class_methods do

      def default_json_container_attribute
        @default_json_container_attribute ||= AttributeDefinition::DEFAULT_CONTAINER_ATTRIBUTE
      end
      def default_json_container_attribute=(v)
        @default_json_container_attribute = v.to_s
      end

      # Type can be a symbol that will be looked up in `ActiveModel::Type.lookup`,
      # or an ActiveModel:::Type::Value)
      #
      # TODO, doc all params. Raise on bad keyword params.
      #
      # @param rails_attribute [Boolean] (keyword) Create an actual ActiveRecord `attribute`.
      #    not needed for our functionality, but registering thusly will let the
      #    type be picked up by simple_form and other tools that may look for it
      #    via ActiveRecord/ActiveModel API.
      def json_attribute(name, type,
                         container_attribute: self.default_json_container_attribute,
                         **options)

        # TODO arg check container_attribute make sure it exists. Hard cause
        # schema isn't loaded yet when class def is loaded. Maybe not.

        # Want to lazily add an attribute cover to the json container attribute,
        # only if it hasn't already been done. WARNING we are using internal
        # Rails API here, but only way to do this lazily, which I thought was
        # worth it.
        unless attributes_to_define_after_schema_loads[container_attribute.to_s] &&
               attributes_to_define_after_schema_loads[container_attribute.to_s].first.is_a?(JsonAttribute::Type::ContainerAttribute)
            attribute container_attribute.to_sym, JsonAttribute::Type::ContainerAttribute.new(self, container_attribute)
        end

        self.json_attributes_registry = json_attributes_registry.with(
          AttributeDefinition.new(name.to_sym, type, options.merge(container_attribute: container_attribute))
        )

        # By default, automatically validate nested models
        if type.kind_of?(JsonAttribute::Type::Model) && options[:validate] != false
          self.validates_with ActiveRecord::Validations::AssociatedValidator, attributes: [name.to_sym]
        end

        # We don't actually use this for anything, we provide our own covers. But registering
        # it with usual system will let simple_form and maybe others find it.
        if options[:rails_attribute]
          self.attribute name.to_sym, self.json_attributes_registry.fetch(name).type
        end

        _json_attributes_module.module_eval do
          define_method("#{name}=") do |value|
            attribute_def = self.class.json_attributes_registry.fetch(name.to_sym)
            # write_store_attribute copied from Rails store_accessor implementation.
            # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96

            # special handling for nil, sorry, because if name key was previously
            # not present, write_store_attribute by default will decide there was
            # no change and refuse to make the change. TODO messy.
            if value.nil? && !public_send(attribute_def.container_attribute).has_key?(attribute_def.store_key)
               public_send :"#{attribute_def.container_attribute}_will_change!"
               public_send(attribute_def.container_attribute)[attribute_def.store_key] = nil
            else
              # use of `write_store_attribute` is copied from Rails store_accessor implementation.
              # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96
              write_store_attribute(attribute_def.container_attribute, attribute_def.store_key, attribute_def.cast(value))
            end
          end

          define_method("#{name}") do
            attribute_def = self.class.json_attributes_registry.fetch(name.to_sym)

            # use of `read_store_attribute` is copied from Rails store_accessor implementation.
            # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96
            read_store_attribute(attribute_def.container_attribute, attribute_def.store_key)
          end
        end
      end

      private

      # Define an anonymous module and include it, so can still be easily
      # overridden by concrete class. Design cribbed from ActiveRecord::Store
      # https://github.com/rails/rails/blob/4590d7729e241cb7f66e018a2a9759cb3baa36e5/activerecord/lib/active_record/store.rb
      def _json_attributes_module # :nodoc:
        @_json_attributes_module ||= begin
          mod = Module.new
          include mod
          mod
        end
      end
    end
  end
end
