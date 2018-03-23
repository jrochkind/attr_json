require 'json_attribute/attribute_definition'

module JsonAttribute
  class AttributeDefinition
    # Attached to a class to record the json attributes registered,
    #  with either JsonAttribute::Record or JsonAttribute::Model.
    #
    # Think of it as mostly like a hash keyed by attribute name, value
    # an AttributeDefinition.
    #
    # It is expected to be used by JsonAttribute::Record and JsonAttribute::Model,
    # you shouldn't need to interact with it directly.
    #
    # It is intentionally immutable to make it harder to accidentally mutate
    # a registry shared with superclass in a `class_attribute`, instead of
    # properly assigning a new modified registry.
    #
    #     self.some_registry_attribute = self.some_registry_attribute.with(
    #        attr_definition_1, attr_definition_2
    #     )
    #     # => Returns a NEW AttributeDefinition object
    #
    # All references in code to "definition" are to a JsonAttribute::AttributeDefinition instance.
    class Registry
      def initialize(hash = {})
        @name_to_definition = hash
        @store_key_to_definition = {}
        definitions.each { |d| store_key_index!(d) }
      end

      def fetch(key, *args, &block)
        @name_to_definition.fetch(key.to_sym, *args, &block)
      end

      def [](key)
        @name_to_definition[key.to_sym]
      end

      def attribute_registered?(key)
        @name_to_definition.has_key?(key.to_sym)
      end

      # Can return nil if none found.
      def store_key_lookup(container_attribute, store_key)
        @store_key_to_definition[container_attribute.to_s] &&
          @store_key_to_definition[container_attribute.to_s][store_key.to_s]
      end

      def definitions
        @name_to_definition.values
      end

      def container_attributes
        @store_key_to_definition.keys.collect(&:to_s)
      end

      # This is how you register additional definitions, as a non-mutating
      # return-a-copy operation.
      def with(*definitions)
        self.class.new(@name_to_definition).tap do |copied|
          definitions.each do |defin|
            copied.add!(defin)
          end
        end
      end

      protected

      def add!(definition)
        if @name_to_definition.has_key?(definition.name)
          raise ArgumentError, "Can't add, conflict with existing attribute name `#{definition.name.to_sym}`: #{@name_to_definition[definition.name].original_args}"
        end
        @name_to_definition[definition.name.to_sym] = definition
        store_key_index!(definition)
      end

      def store_key_index!(definition)
        container_hash = (@store_key_to_definition[definition.container_attribute.to_s] ||= {})

        if container_hash.has_key?(definition.store_key.to_s)
          existing = container_hash[definition.store_key.to_s]
          raise ArgumentError, "Can't add, store key `#{definition.store_key}` conflicts with existing attribute: #{existing.original_args}"
        end

        container_hash[definition.store_key.to_s] = definition
      end
    end
  end
end
