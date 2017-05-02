module JsonAttribute
  module Type
    # An ActiveModel::Type representing a particular JsonAttribute::Model
    # class, supporting casting, serialization, and deserialization from/to
    # JSON-able serializable hashes.
    #
    # You create one with JsonAttribute::Model::Type.new(json_attribute_model_class),
    # but normally that's only done in JsonAttribute::Model.to_type, there isn't
    # an anticipated need to create from any other place.
    class Model < ::ActiveModel::Type::Value
      attr_accessor :model
      def initialize(model)
        #TODO type check, it really better be a JsonAttribute::Model. maybe?
        @model = model
      end

      def type
        model.to_param.underscore.to_sym
      end

      def cast(v)
        if v.nil?
          # TODO should we insist on an empty hash instead?
          v
        elsif v.kind_of? model
          v
        elsif v.respond_to?(:to_hash)
          # to_hash is actually the 'implicit' conversion, it really is a hash
          # even though it isn't is_a?(Hash), try to_hash first before to_h,
          # the explicit conversion.
          model.new(v.to_hash)
        elsif v.respond_to?(:to_h)
          model.new(v.to_h)
        else
          # Bad input? Most existing ActiveModel::Types seem to decide
          # either nil, or a base value like the empty string. They don't
          # raise. So we won't either, just nil.
          nil
        end
      end

      def serialize(v)
        if v.nil?
          nil
        elsif v.kind_of?(model)
          v.serializable_hash
        else
          cast(v).serializable_hash
        end
      end

      def deserialize(v)
        cast(v)
      end

      # these guys are definitely mutable, so we need this.
      def changed_in_place?(raw_old_value, new_value)
        serialize(new_value) != raw_old_value
      end
    end
  end
end
