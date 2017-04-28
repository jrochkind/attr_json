module JsonAttribute
  class ArrayType
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
  end
end
