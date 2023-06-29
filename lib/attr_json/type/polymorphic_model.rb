module AttrJson
  module Type
    # AttrJson::Type::PolymorphicModel can be used to create attr_json attributes
    # that can hold any of various specified AttrJson::Model models. It is a
    # _somewhat_ experimental feature.
    #
    # "polymorphic" may not be quite the right word, but we use it out of analogy
    # with ActiveRecord [polymorphic assocications](http://guides.rubyonrails.org/association_basics.html#polymorphic-associations),
    # which it resembles, as well as ActiveRecord [Single-Table Inheritance](http://guides.rubyonrails.org/association_basics.html#single-table-inheritance).
    #
    # Similar to these AR features, a PolymorphicModel-typed attribute will serialize the
    # _model name_ of a given value in a `type` json hash key, so it can deserialize
    # to the same correct model class.
    #
    # It can be used for single-model attributes, or arrays (which can be hetereogenous),
    # in either AttrJson::Record or nested AttrJson::Models. If `CD`, `Book`, `Person`,
    # and `Corporation` are all AttrJson::Model classes:
    #
    #      attr_json :favorite, AttrJson::Type::PolymorphicAttribute.new(CD, Book)
    #      attr_json :authors, AttrJson::Type::PolymorphicAttribute.new(Person, Corporation), array: true
    #
    # Currently, you need a specific enumerated list of allowed types, and they all
    # need to be AttrJson::Model classes. You can't at the moment have an "open" polymorphic
    # type that can accept any AttrJson::Model.
    #
    # You can change the json key that the "type" (class name) for a value is stored to,
    # when creating the type:
    #
    #      attr_json, :author, AttrJson::Type::PolymorphicAttribute.new(Person, Corporation, type_key: "__type__")
    #
    # But if you already have existing data in the db, that's gonna be problematic to change on the fly.
    #
    # You can set attributes with a hash, but it needs to have an appropriate `type` key
    # (or other as set by `type_key` arg). If it does not, or you try to set a non-hash
    # value, you will get a AttrJson::Type::PolymorphicModel::TypeError. (maybe a validation
    # error would be better? but it's not what it does now.)
    #
    # **Note** this
    # also applies to loading non-compliant data from the database. If you have non-compliant
    # data in the db, the only way to look at it will be as a serialized json string in top-level
    # {#json_attributes_before_cast} (or other relevant container attribute.)
    #
    # There is no built-in form support for PolymorphicModels, you'll have to work it out.
    #
    # ## jsonb_contains support
    #
    # There is basic jsonb_contains support, but no sophisticated type-casting like normal, beyond
    # the polymorphic attribute. But you can do:
    #
    #      MyRecord.jsonb_contains(author: { name: "foo"})
    #      MyRecord.jsonb_contains(author: { name: "foo", type: "Corporation"})
    #      MyRecord.jsonb_contains(author: Corporation.new(name: "foo"))
    #
    # Additionally, there is not_jsonb_contains, which creates the same query terms like jsonb_contains, but negated.
    #
    class PolymorphicModel < ActiveModel::Type::Value
      class TypeError < ::TypeError ; end

      attr_reader :type_key, :unrecognized_type, :model_type_lookup
      def initialize(*args)
        options = { type_key: "type", unrecognized_type: :raise}.merge(
          args.extract_options!.assert_valid_keys(:type_key, :unrecognized_type)
        )
        @type_key = options[:type_key]
        @unrecognized_type = options[:unrecognized_type]

        model_types = args

        model_types.collect! do |m|
          if m.respond_to?(:ancestors) && m.ancestors.include?(AttrJson::Model)
            m.to_type
          else
            m
          end
        end

        if bad_arg = model_types.find { |m| !m.is_a? AttrJson::Type::Model }
          raise ArgumentError, "#{self.class.name} only works with AttrJson::Model / AttrJson::Type::Model, not '#{bad_arg.inspect}'"
        end
        if type_key_conflict = model_types.find { |m| m.model.attr_json_registry.has_attribute?(@type_key) }
          raise ArgumentError, "conflict between type_key '#{@type_key}' and an existing attr_json in #{type_key_conflict.model}"
        end

        @model_type_lookup = model_types.collect do |type|
          [type.model.name, type]
        end.to_h
      end

      def model_names
        model_type_lookup.keys
      end

      def model_types
        model_type_lookup.values
      end

      # ActiveModel method, symbol type label
      def type
        @type ||= "any_of_#{model_types.collect(&:type).collect(&:to_s).join('_')}".to_sym
      end

      def cast(v)
        cast_or_deserialize(v, :cast)
      end

      def deserialize(v)
        cast_or_deserialize(v, :deserialize)
      end

      def serialize(v)
        return nil if v.nil?

        # if it's not already a model cast it to a model if possible (eg it's a hash)
        v = cast(v)

        model_name = v.class.name
        type = type_for_model_name(model_name)

        raise_bad_model_name(model_name, v) if type.nil?

        type.serialize(v).merge(type_key => model_name)
      end

      def type_for_model_name(model_name)
        model_type_lookup[model_name]
      end

      # This is used only by our own keypath-chaining query stuff.
      # For PolymorphicModel type, it does no type casting, just
      # sticks whatever you gave it in, which needs to be json-compat
      # values.
      def value_for_contains_query(key_path_arr, value)
        hash_arg = {}
        key_path_arr.each.with_index.inject(hash_arg) do |hash, (n, i)|
          if i == key_path_arr.length - 1
            hash[n] = value
          else
            hash[n] = {}
          end
        end
        hash_arg
      end

      protected

      # We need to make sure to call the correct operation on
      # the model type, so that we get the same result as if
      # we had called the type directly
      #
      # @param v [Object, nil] the value to cast or deserialize
      # @param operation [Symbol] :cast or :deserialize
      def cast_or_deserialize(v, operation)
        if v.nil?
          v
        elsif model_names.include?(v.class.name)
          v
        elsif v.respond_to?(:to_hash)
          model_from_hash(v.to_hash, operation)
        elsif v.respond_to?(:to_h)
          model_from_hash(v.to_h, operation)
        else
          raise_bad_model_name(v.class, v)
        end
      end

      # @param hash [Hash] the value to cast or deserialize
      # @param operation [Symbol] :cast or :deserialize
      def model_from_hash(hash, operation)
        new_hash = hash.stringify_keys
        model_name = new_hash.delete(type_key.to_s)

        raise_missing_type_key(hash) if model_name.nil?

        type = type_for_model_name(model_name)

        raise_bad_model_name(model_name, hash) if type.nil?

        if operation == :deserialize
          type.deserialize(new_hash)
        elsif operation == :cast
          type.cast(new_hash)
        else
          raise ArgumentError, "Unknown operation #{operation}"
        end
      end

      def raise_missing_type_key(value)
        raise TypeError, "AttrJson::Type::Polymorphic can't cast without '#{type_key}' key: #{value}"
      end

      def raise_bad_model_name(name, value)
        raise TypeError, "This AttrJson::Type::PolymorphicType can only include {#{model_names.join(', ')}}, not '#{name}': #{value.inspect}"
      end
    end
  end
end
