module JsonAttribute
  module Type
    # You can wrap any ActiveModel::Type in one of these, and it's magically
    # a type representing an Array of those things, always returning
    # an array of those things on cast, serialize, and deserialize.
    #
    # Meant for use with JsonAttribute::Record and JsonAttribute::Model, may or
    # may not do something useful or without exceptions in other contexts.
    #
    #     JsonAttribute::Type::Array.new(base_type)
    class Array
      attr_reader :base_type
      def initialize(base_type)
        @base_type = base_type
      end

      def cast(value)
        Array(value).collect { |v| base_type.cast(v) }
      end

      def serialize(value)
        Array(value).collect { |v| base_type.serialize(v) }
      end

      def deserialize(value)
        Array(value).collect { |v| base_type.deserialize(v) }
      end

      # This is used only by our own keypath-chaining query stuff. Yes, it's
      # a bit confusing, sorry.
      def add_keypath_component_to_query(current_hash, attribute_definition, key)
        array = current_hash[attribute_definition.store_key] ||= []
        array << {} if array.empty?
        leaf_hash = array.first

        next_attr_def = base_type.model.json_attributes_registry.fetch(key)

        return leaf_hash, next_attr_def
      end
    end
  end
end
