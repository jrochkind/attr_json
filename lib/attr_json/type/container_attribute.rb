module AttrJson
  module Type
    # A type that gets applied to the AR container/store jsonb attribute,
    # to do serialization/deserialization/cast using declared attr_jsons,
    # before calling super to original ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb
    class ContainerAttribute < ActiveRecord::ConnectionAdapters::PostgreSQL::OID::Jsonb
      attr_reader :model, :container_attribute
      def initialize(model, container_attribute)
        @model = model
        @container_attribute = container_attribute.to_s
      end
      def cast(v)
        # this seems to be rarely/never called by AR, not sure where if ever.
        h = super || {}
        model.attr_json_registry.definitions.each do |attr_def|
          next unless container_attribute.to_s == attr_def.container_attribute.to_s

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
          attr_def = model.attr_json_registry.store_key_lookup(container_attribute, key)
          [key, attr_def ? attr_def.serialize(value) : value]
        end.to_h)
      end
      def deserialize(v)
        h = super || {}
        model.attr_json_registry.definitions.each do |attr_def|
          next unless container_attribute.to_s == attr_def.container_attribute.to_s

          if h.has_key?(attr_def.store_key)
            h[attr_def.store_key] = attr_def.deserialize(h[attr_def.store_key])
          elsif attr_def.has_default?
            h[attr_def.store_key] = attr_def.provide_default!
          end
        end
        h
      end
    end
  end
end
