 require 'attr_json/type/array'

 module AttrJson

  # Represents a `attr_json` definition, on either a AttrJson::Record
  # or AttrJson::Model. Normally this class is only used by
  # AttrJson::AttributeDefinition::{Registry}.
  class AttributeDefinition
    NO_DEFAULT_PROVIDED = Object.new.freeze
    VALID_OPTIONS = %i{container_attribute store_key default array}.freeze

    attr_reader :name, :type, :original_args, :container_attribute

    # @param name [Symbol,String]
    # @param type [Symbol,ActiveModel::Type::Value] Symbol is looked up in
    #   ActiveRecord::Type.lookup, but with `adapter: nil` for no custom
    #   adapter-specific lookup.
    #
    # @option options store_key [Symbol,String]
    # @option options container_attribute [Symbol,ActiveModel::Type::Value]
    #   Only means something in a AttrJson::Record, no meaning in a AttrJson::Model.
    # @option options default [Object,Symbol,Proc] (nil)
    # @option options array [Boolean] (false)
    def initialize(name, type, options = {})
      options.assert_valid_keys *VALID_OPTIONS
      # saving original args for reflection useful for debugging, maybe other things.
      @original_args = [name, type, options]

      @name = name.to_sym

      @container_attribute = options[:container_attribute] && options[:container_attribute].to_s

      @store_key = options[:store_key] && options[:store_key].to_s

      @default = if options.has_key?(:default)
        options[:default]
      elsif options[:array] == true
        -> { [] }
      else
        NO_DEFAULT_PROVIDED
      end

      type = self.class.lookup_type(type)

      @type = (options[:array] == true ? AttrJson::Type::Array.new(type) : type)
    end

    def cast(value)
      type.cast(value)
    end

    def serialize(value)
      type.serialize(value)
    end

    def deserialize(value)
      type.deserialize(value)
    end

    def has_custom_store_key?
      !!@store_key
    end

    def store_key
      (@store_key || name).to_s
    end

    def has_default?
      @default != NO_DEFAULT_PROVIDED
    end

    # Can be value or proc!
    def default_argument
      return nil unless has_default?
      @default
    end

    def provide_default!
      unless has_default?
        raise ArgumentError.new("This #{self.class.name} does not have a default defined!")
      end

      # Seems weird to assume a Proc can't be the default itself, but I guess
      # Proc's aren't serializable, so fine assumption. Modeled after:
      # https://github.com/rails/rails/blob/f2dfd5c6fdffdf65e6f07aae8e855ac802f9302f/activerecord/lib/active_record/attribute/user_provided_default.rb#L12-L16
      if @default.is_a?(Proc)
        cast(@default.call)
      else
        cast(@default)
      end
    end

    def array_type?
      type.is_a? AttrJson::Type::Array
    end

    # Used for figuring out appropriate behavior for nested attribute implementation among
    # other places. true if type is a nested model, either straight or polymorphic
    def single_model_type?
      self.class.single_model_type?(type)
    end

    def self.single_model_type?(arg_type)
      arg_type.is_a?(AttrJson::Type::Model) || arg_type.is_a?(AttrJson::Type::PolymorphicModel)
    end

    # Used for figuring out appropriate behavior in nested attribute implementation among
    # other places. true if type is an array of things that are not nested models.
    def array_of_primitive_type?
      array_type? && !self.class.single_model_type?(type.base_type)
    end

    # Can look up a symbol to a type, or leave a type alone, or raise if it's neither.
    # Extracted into a method, so it can be called from AttrJson::Model#attr_json, for
    # some timezone aware shenanigans.
    def self.lookup_type(type)
      if type.is_a? Symbol
        # ActiveModel::Type.lookup may make more sense, but ActiveModel::Type::Date
        # seems to have a bug with multi-param assignment. Mostly they return
        # the same types, but ActiveRecord::Type::Date works with multi-param assignment.
        #
        # We pass `adapter: nil` to avoid triggering a db connection.
        # See: https://github.com/jrochkind/attr_json/issues/41
        # This is at the "cost" of not using any adapter-specific types... which
        # maybe preferable anyway?
        #
        # AND we add precision for datetime/time types... since we're using Rails json
        # serializing, we're kind of stuck with this precision in current implementation.
        lookup_kwargs = { adapter: nil }
        if type == :datetime || type == :time
          lookup_kwargs = { precision: ActiveSupport::JSON::Encoding.time_precision }
        end

        type = ActiveRecord::Type.lookup(type, **lookup_kwargs)
      elsif !(type.is_a?(ActiveModel::Type::Value) || type.is_a?(ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter))
        raise ArgumentError, "Second argument (#{type}) must be a symbol or instance of an ActiveModel::Type::Value subclass"
      end
      type
    end

  end
end
