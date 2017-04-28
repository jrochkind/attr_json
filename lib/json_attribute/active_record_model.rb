require 'json_attribute/attribute_definition'

module JsonAttribute
  module ActiveRecordModel
    extend ActiveSupport::Concern

    # A type that gets applied to the AR container/store jsonb attribute,
    # to do serialization/deserialization/cast using declared json_attributes,
    # before calling super to original ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb
    class ContainerAttributeType < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb
      attr_reader :model
      def initialize(model)
        @model = model
      end
      def cast(v)
        h = super || {}
        model.json_attributes_registry.values.each do |attr_def|
          if h.has_key?(attr_def.store_key)
            h[attr_def.store_key] = attr_def.cast(h[attr_def.store_key])
          elsif attr_def.has_default?
            h[attr_def.store_key] = attr_def.provide_default!
          end
        end
        h
      end
      def serialize(v)
        if v.nil?
          return super
        end

        super(v.collect do |key, value|
          # TODO inefficient, cache somehow? We need a Registry class.
          attr_def = model.json_attributes_registry.values.find { |d| d.store_key == key }
          [key, attr_def ? attr_def.serialize(value) : value]
        end.to_h)
      end
      def deserialize(v)
        h = super || {}
        model.json_attributes_registry.values.each do |attr_def|
          if h.has_key?(attr_def.store_key)
            h[attr_def.store_key] = attr_def.deserialize(h[attr_def.store_key])
          elsif attr_def.has_default?
            h[attr_def.store_key] = attr_def.provide_default!
          end
        end
        h
      end
    end

    included do
      # TODO make sure it's included in an AR model, or raise.
      class_attribute :json_attributes_registry, instance_accessor: false
      self.json_attributes_registry = {}
    end


    class_methods do
      # Type can be a symbol that will be looked up in `ActiveModel::Type.lookup`,
      # or anything that's an ActiveSupport::Type-like thing (usually
      # subclassing ActiveSupport::Type::Value)
      #
      # TODO, doc or
      def json_attribute(name, type,
                         container_attribute: AttributeDefinition::DEFAULT_CONTAINER_ATTRIBUTE,
                         **options)
        self.json_attributes_registry = json_attributes_registry.merge(
          name.to_sym => AttributeDefinition.new(name.to_sym, type, options.merge(container_attribute: container_attribute))
        )

        _json_attributes_module.module_eval do
          define_method("#{name}=") do |value|
            attribute_def = self.class.json_attributes_registry.fetch(name.to_sym)

            # write_store_attribute copied from Rails store_accessor implementation.
            # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96
            write_store_attribute(attribute_def.container_attribute, attribute_def.store_key, attribute_def.cast(value))
          end

          define_method("#{name}") do
            attribute_def = self.class.json_attributes_registry.fetch(name.to_sym)

            # read_store_attribute copied from Rails store_accessor implementation.
            # https://github.com/rails/rails/blob/74c3e43fba458b9b863d27f0c45fd2d8dc603cbc/activerecord/lib/active_record/store.rb#L90-L96
            from_hash_value = read_store_attribute(attribute_def.container_attribute, attribute_def.store_key)
return from_hash_value
            # If this already is of the correct cast type, cast will generally
            # quickly return itself, so this is actually a cheap way to lazily
            # convert and memoize serialized verison to proper in-memory object.
            # They'll be properly serialized out by Rails.... we think. Might
            # need a custom serializer on the json attribute, we'll see.
            # casted = attribute_def.deserialize(from_hash_value)
            # unless casted.equal?(from_hash_value)
            #   write_store_attribute(attribute_def.container_attribute, name.to_s, casted)
            # end

            # return casted
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
