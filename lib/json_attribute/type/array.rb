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
        convert_to_array(value).collect { |v| base_type.cast(v) }
      end

      def serialize(value)
        convert_to_array(value).collect { |v| base_type.serialize(v) }
      end

      def deserialize(value)
        convert_to_array(value).collect { |v| base_type.deserialize(v) }
      end

      # This is used only by our own keypath-chaining query stuff.
      def value_for_contains_query(key_path_arr, value)
        [
          if key_path_arr.present?
            base_type.value_for_contains_query(key_path_arr, value)
          else
            base_type.serialize(base_type.cast value)
          end
        ]
      end

      protected
      def convert_to_array(value)
        if value.kind_of?(Hash)
          [value]
        else
          Array(value)
        end
      end

    end
  end
end
