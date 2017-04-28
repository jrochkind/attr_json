require 'json_attribute/attribute_definition'

module JsonAttribute
  class AttributeDefinition
    # Attached to a class to registers the json attributes registered,
    #  with either JsonAttribute::Record or JsonAttribute::Module.
    #
    # Think of it as mostly like a hash keyed by attribute name, value
    # an AttributeDefinition.
    #
    # It is expected to be used by JsonAttribute::Record and JsonAttribute::Module,
    # you shouldn't need to interact with it directly.
    #
    # It is intentionally immutable to make it harder to accidentally mutate
    # a registry shared with superclass in a `class_attribute`, instead of
    # properly assigning a new modified registry.
    #
    #     self.some_registry_attribute = self.some_registry_attribute.with(
    #        attr_definition_1, attr_definition_2
    #     )
    #     # => Returns a NEW AttributeDefintion object
    #
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

      # Can return nil if none found.
      def store_key_lookup(store_key)
        @store_key_to_definition[store_key.to_sym]
      end

      def definitions
        @name_to_definition.values
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
        if @name_to_definition.has_key?(definition.name.to_sym)
          raise ArgumentError "Can't add, conflict with existing attribute name `#{definition.name.to_sym}`: #{defintion}"
        end
        @name_to_definition[definition.name.to_sym] = definition
        store_key_index!(definition)
      end

      def store_key_index!(definition)
        if @store_key_to_definition.has_key?(definition.store_key.to_s)
          raise ArgumentError "Can't add, conflict with existing store_key `#{definition.store_key.to_s}`: #{defintion}"
        end

        @store_key_to_definition[definition.store_key.to_s] = definition
      end
    end
  end
end
