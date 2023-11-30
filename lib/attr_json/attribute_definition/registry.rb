# frozen_string_literal: true

require 'attr_json/attribute_definition'

module AttrJson
  class AttributeDefinition
    # Attached to a class to record the json attributes registered,
    #  with either AttrJson::Record or AttrJson::Model.
    #
    # Think of it as mostly like a hash keyed by attribute name, value
    # an AttributeDefinition.
    #
    # It is expected to be used by AttrJson::Record and AttrJson::Model,
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
    # All references in code to "definition" are to a AttrJson::AttributeDefinition instance.
    class Registry
      def initialize(hash = {})
        @name_to_definition = hash.dup
        @store_key_to_definition = {}
        definitions.each { |d| store_key_index!(d) }

        @container_attributes_registered = Hash.new { Set.new }
      end

      def fetch(key, *args, &block)
        @name_to_definition.fetch(key.to_sym, *args, &block)
      end

      def [](key)
        @name_to_definition[key.to_sym]
      end

      def has_attribute?(key)
        @name_to_definition.has_key?(key.to_sym)
      end

      def type_for_attribute(key)
        self[key].type
      end

      # Can return nil if none found.
      def store_key_lookup(container_attribute, store_key)
        @store_key_to_definition[AttrJson.efficient_to_s(container_attribute)] &&
          @store_key_to_definition[AttrJson.efficient_to_s(container_attribute)][AttrJson.efficient_to_s(store_key)]
      end

      def definitions
        @name_to_definition.values
      end

      # Returns all registered attributes as an array of symbols
      def attribute_names
        @name_to_definition.keys
      end

      def container_attributes
        @store_key_to_definition.keys.collect { |s| AttrJson.efficient_to_s(s) }
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


      # We need to lazily set the container type only the FIRST time
      #
      # While also avoiding this triggering ActiveRecord to actually go to DB,
      # we don't want DB connection forced on boot, that's a problem for many apps,
      # including that may not have a DB connection in initial development.
      # (#type_for_attribute forces DB connection)
      #
      # AND we need to call container attriubte on SUB-CLASS AGAIN, iff sub-class
      # has any of it's own new registrations, to make sure we get the right type in
      # sub-class!
      #
      # So we just keep track of whether we've registered ourselves, so we can
      # first time we need to.
      #
      # While current implementation is simple, this has ended up a bit fragile,
      # a different API that doesn't require us to do this implicitly lazily
      # might be preferred! But this is what we got for now.
      def register_container_attribute(attribute_name:, model:)
        @container_attributes_registered[attribute_name.to_sym] << model
      end

      def container_attribute_registered?(attribute_name:, model:)
         @container_attributes_registered[attribute_name.to_sym].include?(model)
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
        container_hash = (@store_key_to_definition[AttrJson.efficient_to_s(definition.container_attribute)] ||= {})

        if container_hash.has_key?(AttrJson.efficient_to_s(definition.store_key))
          existing = container_hash[AttrJson.efficient_to_s(definition.store_key)]
          raise ArgumentError, "Can't add, store key `#{definition.store_key}` conflicts with existing attribute: #{existing.original_args}"
        end

        container_hash[AttrJson.efficient_to_s(definition.store_key)] = definition
      end
    end
  end
end
