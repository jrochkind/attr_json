# frozen_string_literal: true

require 'active_support/concern'
require 'active_model/type'

require 'attr_json/attribute_definition'
require 'attr_json/attribute_definition/registry'

require 'attr_json/type/model'
require 'attr_json/model/cocoon_compat'
require 'attr_json/model/nested_model_validator'

require 'attr_json/serialization_coder_from_type'

module AttrJson

  # Meant for use in a plain class, turns it into an ActiveModel::Model
  # with attr_json support. NOT for use in an ActiveRecord::Base model,
  # see `Record` for ActiveRecord use.
  #
  # Creates an ActiveModel object with _typed_ attributes, easily serializable
  # to json, and with a corresponding ActiveModel::Type representing the class.
  # Meant for use as an attribute of a AttrJson::Record. Can be nested,
  # AttrJson::Models can have attributes that are other AttrJson::Models.
  #
  # @note Includes ActiveModel::Model whether you like it or not.
  #
  # You can control what happens if you set an unknown key (one that you didn't
  # register with `attr_json`) with the config attribute `attr_json_config(unknown_key:)`.
  # * :raise (default) raise ActiveModel::UnknownAttributeError
  # * :strip Ignore the unknown key and do not include it, without raising.
  # * :allow Allow the unknown key and it's value to be in the serialized hash,
  #     and written to the database. May be useful for legacy data or columns
  #     that other software touches, to let unknown keys just flow through.
  #
  #        class Something
  #          include AttrJson::Model
  #          attr_json_config(unknown_key: :allow)
  #          #...
  #        end
  #
  # Similarly, trying to set a Model-valued attribute with an object that
  # can't be cast to a Hash or Model at all will normally raise a
  # AttrJson::Type::Model::BadCast error, but you can set config `bad_cast: :as_nil`
  # to make it cast to nil, more like typical ActiveRecord cast.
  #
  #        class Something
  #          include AttrJson::Model
  #          attr_json_config(bad_cast: :as_nil)
  #          #...
  #        end
  #
  # ## Date-type timezone conversion
  #
  # By default, AttrJson::Model date/time attributes will be
  # [ActiveRecord timezone-aware](https://api.rubyonrails.org/classes/ActiveRecord/Timestamp.html)
  # based on settings of `config.active_record.time_zone_aware_attributes` and
  # `ActiveRecord::Base.time_zone_aware_types`.
  #
  # If you'd like to override this, you can set:
  #
  # ```
  # attr_json_config(time_zone_aware_attributes: true)
  # attr_json_config(time_zone_aware_attributes: false)
  # attr_json_config(time_zone_aware_attributes: [:datetime, :time]) # custom list of types
  # ```
  #
  # ## ActiveRecord `serialize`
  #
  # If you want to map a single AttrJson::Model to a json/jsonb column, you
  # can use ActiveRecord `serialize` feature.
  #
  # https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Serialization/ClassMethods.html
  #
  # We provide a simple shim to give you the right API for a "coder" for AR serialize:
  #
  # class ValueModel
  #   include AttrJson::Model
  #   attr_json :some_string, :string
  # end
  #
  # class SomeModel < ApplicationRecord
  #   serialize :some_json_column, ValueModel.to_serialize_coder
  # end
  #
  # # Strip nils
  #
  # When embedded in an `attr_json` attribute, models are normally serialized with `nil` values
  # stripped from hash where possible, for a more compact representation.
  # This can be set differently in the type.
  #
  #     attr_json :lang_and_value, LangAndValue.to_type(strip_nils: false)
  #
  # See #serializable_hash docs for possible values.
  module Model
    extend ActiveSupport::Concern

    include ActiveModel::Model
    include ActiveModel::Serialization
    #include ActiveModel::Dirty

    included do
      if self < ActiveRecord::Base
        raise TypeError, "AttrJson::Model is not for an ActiveRecord::Base model. #{self} appears to be one. Are you looking for ::AttrJson::Record?"
      end

      class_attribute :attr_json_registry, instance_accessor: false
      self.attr_json_registry = ::AttrJson::AttributeDefinition::Registry.new
    end

    class_methods do
      def attr_json_config(new_values = {})
        if new_values.present?
          # get one without new values, then merge new values into it, and
          # set it locally for this class.
          @attr_json_config = attr_json_config.merge(new_values)
        else
          if instance_variable_defined?("@attr_json_config")
            # we have a custom one for this class, return it.
            @attr_json_config
          elsif superclass.respond_to?(:attr_json_config)
            # return superclass without setting it locally, so changes in superclass
            # will continue effecting us.
            superclass.attr_json_config
          else
            # no superclass, no nothing, set it to blank one.
            @attr_json_config = Config.new(mode: :model)
          end
        end
      end


      # The inverse of model#serializable_hash -- re-hydrates a serialized hash to a model.
      #
      # Similar to `.new`, but translates things that need to be translated in deserialization,
      # like store_keys, and properly calling deserialize (rather than cast) on the underlying types.
      #
      # @example Model.new_from_serializable(hash)
      def new_from_serializable(attributes = {})
        attributes = attributes.collect do |key, value|
          # store keys in arguments get translated to attribute names on initialize.
          if attribute_def = self.attr_json_registry.store_key_lookup("".freeze, AttrJson.efficient_to_s(key))
            key = AttrJson.efficient_to_s(attribute_def.name)
          end

          attr_type = self.attr_json_registry.has_attribute?(key) && self.attr_json_registry.type_for_attribute(key)
          if attr_type
            value = attr_type.deserialize(value)
          end

          [key, value]
        end.to_h

        self.new(attributes)
      end

      # @returns ActiveModel::Type suitable for including this model in
      # an AttrJson::Record or ::Model attribute
      #
      # @param strip_nils [Boolean,Symbol] [true,false,:safely] as a type,
      #   should we strip nils when serializing? By default this type strips
      #   nils in :safely mode. See AttrJson::Model#serializable_hash
      def to_type(strip_nils: :safely)
        @type ||= AttrJson::Type::Model.new(self, strip_nils: strip_nils)
      end

      # An ActiveModel::Type that can be used to serialize this model
      # across an entire JSON(b) column.
      #
      # @example using standard ActiveRecord `serialize` feature.
      #
      #     class MyTable < ApplicationRecord
      #       serialize :some_json_column, MyModel.to_serialization_coder
      #
      #       # In Rails 7.1+:
      #       # serialize :some_json_column, coder: MyModel.to_serialization_coder
      #     end
      #
      def to_serialization_coder
        @serialization_coder ||= AttrJson::SerializationCoderFromType.new(to_type)
      end

      # like the ActiveModel::Attributes method
      def attribute_names
        attr_json_registry.attribute_names
      end

      # like the ActiveModel::Attributes method, hash with name keys, and ActiveModel::Type values
      def attribute_types
        attribute_names.collect { |name| [AttrJson.efficient_to_s(name), attr_json_registry.type_for_attribute(name)]}.to_h
      end


      # Type can be an instance of an ActiveModel::Type::Value subclass, or a symbol that will
      # be looked up in `ActiveModel::Type.lookup`
      #
      # @param name [Symbol,String] name of attribute
      #
      # @param type [ActiveModel::Type::Value] An instance of an ActiveModel::Type::Value (or subclass)
      #
      # @option options [Boolean] :array (false) Make this attribute an array of given type.
      #    Array types default to an empty array. If you want to turn that off, you can add
      #    `default: AttrJson::AttributeDefinition::NO_DEFAULT_PROVIDED`
      #
      # @option options [Object] :default (nil) Default value, if a Proc object it will be #call'd
      #   for default.
      #
      # @option options [String,Symbol] :store_key (nil) Serialize to JSON using
      #   given store_key, rather than name as would be usual.
      #
      # @option options [Boolean] :validate (true) Mak validation errors on the attributes post up
      #   to self, using something similar to an ActiveRecord::Validations::AssociatedValidator
      def attr_json(name, type, **options)
        options.assert_valid_keys(*(AttributeDefinition::VALID_OPTIONS - [:container_attribute] + [:validate]))

        type = _attr_json_maybe_wrap_timezone_aware(type)

        self.attr_json_registry = attr_json_registry.with(
          AttributeDefinition.new(name.to_sym, type, options.except(:validate))
        )

        # By default, automatically validate nested models
        if type.kind_of?(AttrJson::Type::Model) && options[:validate] != false
          # Post validations up with something based on ActiveRecord::Validations::AssociatedValidator
          self.validates_with ::AttrJson::Model::NestedModelValidator, attributes: [name.to_sym]
        end

        _attr_jsons_module.module_eval do
          define_method("#{name}=") do |value|
            _attr_json_write(AttrJson.efficient_to_s(name), value)
          end

          define_method("#{name}") do
            attributes[AttrJson.efficient_to_s(name)]
          end
        end
      end

      private

      # Define an anonymous module and include it, so can still be easily
      # overridden by concrete class. Design cribbed from ActiveRecord::Store
      # https://github.com/rails/rails/blob/4590d7729e241cb7f66e018a2a9759cb3baa36e5/activerecord/lib/active_record/store.rb
      def _attr_jsons_module # :nodoc:
        @_attr_jsons_module ||= begin
          mod = Module.new
          include mod
          mod
        end
      end

      # wrap in ActiveRecord type for timezone-awareness/conversion, if needed
      # We at present only need this in AttrJson::Model cause in AttrJson::Record,
      # our sync with ActiveRecord attributes takes care of it for us.
      # See https://github.com/rails/rails/blob/v7.0.4/activerecord/lib/active_record/attribute_methods/time_zone_conversion.rb#L78
      #
      # For now we use ActiveRecord::Base state to decide.
      #
      # We have to turn a symbol type into a real object type if we want to wrap it -- we will
      # return an actual ActiveModel::Value::Type either way, converting from symbol!
      #
      # That *wrapped* type will be the new type, registered with AttributeDefinition
      # and then with Rails `attribute`, to provide timezone conversion.
      def _attr_json_maybe_wrap_timezone_aware(type)
        type = AttributeDefinition.lookup_type(type)

        if self.attr_json_config.time_zone_aware_attributes.nil?
          # nil config means use ActiveRecord::Base
          aware       = ActiveRecord::Base.time_zone_aware_attributes
          aware_types = ActiveRecord::Base.time_zone_aware_types
        elsif self.attr_json_config.time_zone_aware_attributes.kind_of?(Array)
          # Array config means we're doing it, and these are the types
          aware       = true
          aware_types = self.attr_json_config.time_zone_aware_attributes
        else
          # boolean config, types from ActiveRecord::Base
          aware       = !!self.attr_json_config.time_zone_aware_attributes
          aware_types = ActiveRecord::Base.time_zone_aware_types
        end

        if aware && aware_types.include?(type.type)
          type = ActiveRecord::AttributeMethods::TimeZoneConversion::TimeZoneConverter.new(type)
        end

        type
      end
    end

    def initialize(attributes = {})
      super

      fill_in_defaults!
    end

    # inspired by https://github.com/rails/rails/blob/8015c2c2cf5c8718449677570f372ceb01318a32/activemodel/lib/active_model/attributes.rb
    def initialize_dup(other) # :nodoc:
      @attributes = @attributes.deep_dup
      super
    end

    def attributes
      @attributes ||= {}
    end

    # ActiveModel method, called in initialize. overridden.
    # from https://github.com/rails/rails/blob/42a16a4d6514f28e05f1c22a5f9125d194d9c7cb/activemodel/lib/active_model/attribute_assignment.rb
    def assign_attributes(new_attributes)
      if !new_attributes.respond_to?(:stringify_keys)
        raise ArgumentError, "When assigning attributes, you must pass a hash as an argument."
      end
      return if new_attributes.empty?

      # stringify keys just like https://github.com/rails/rails/blob/4f99a2186479d5f77460622f2c0f37708b3ec1bc/activemodel/lib/active_model/attribute_assignment.rb#L34
      new_attributes.stringify_keys.each do |k, v|
        setter = :"#{k}="
        if respond_to?(setter)
          public_send(setter, v)
        else
          _attr_json_write_unknown_attribute(k, v)
        end
      end
    end

    # This attribute from ActiveRecord makes SimpleForm happy, and able to detect
    # type.
    def type_for_attribute(attr_name)
      self.class.attr_json_registry.type_for_attribute(attr_name)
    end

    # This attribute from ActiveRecord make SimpleForm happy, and able to detect
    # type.
    def has_attribute?(str)
      self.class.attr_json_registry.has_attribute?(str)
    end

    # like the ActiveModel::Attributes method
    def attribute_names
      self.class.attribute_names
    end

    # Override from ActiveModel::Serialization to:
    #
    # * handle store_key settings
    #
    # * #serialize by type to make sure any values set directly on hash still
    # get properly type-serialized.
    #
    # * custom logic for keeping nil values out of serialization to be more compact
    #
    # @param strip_nils [:symbol, Boolean] (default false) Should we keep keys with
    #   `nil` values out of the serialization entirely? You might want to to keep
    #   your in-database serialization compact. By default this method does not -- but
    #   by default AttrJson::Type::Model sends `:safely` when serializing.
    #     * false => do not strip nils
    #     * :safely => strip nils only when there is no default value for the attribute,
    #       so `nil` can still override the default value
    #     * true => strip nils even if there is a default value -- in AttrJson
    #       context, this means the default will be reapplied over nil on
    #       every de-serialization!
    def serializable_hash(options=nil)
      strip_nils = options&.has_key?(:strip_nils) ? options.delete(:strip_nils) : false

      unless [true, false, :safely].include?(strip_nils)
        raise ArgumentError, ":strip_nils must be true, false, or :safely"
      end

      super(options).collect do |key, value|
        if attribute_def = self.class.attr_json_registry[key.to_sym]
          key = attribute_def.store_key

          value = attribute_def.serialize(value)
        end

        # strip_nils handling
        if value.nil? && (
           (strip_nils == :safely && !attribute_def&.has_default?) ||
            strip_nils == true )
        then
          # do not include in serializable_hash
          nil
        else
          [key, value]
        end
      end.compact.to_h
    end

    # ActiveRecord JSON serialization will insist on calling
    # this, instead of the specified type's #serialize, at least in some cases.
    # So it's important we define it -- the default #as_json added by ActiveSupport
    # will serialize all instance variables, which is not what we want.
    #
    # @param strip_nils [:symbol, Boolean] (default false) [true, false, :safely],
    #   see #serializable_hash
    def as_json(options=nil)
      serializable_hash(options)
    end


    # We deep_dup on #to_h, you want attributes unduped, ask for #attributes.
    def to_h
      attributes.deep_dup
    end

    # Two AttrJson::Model objects are equal if they are the same class
    # AND their #attributes are equal.
    def ==(other_object)
      other_object.class == self.class && other_object.attributes == self.attributes
    end

    # ActiveRecord objects [have a](https://github.com/rails/rails/blob/v5.1.5/activerecord/lib/active_record/nested_attributes.rb#L367-L374)
    # `_destroy`, related to `marked_for_destruction?` functionality used with AR nested attributes.
    # We don't mark for destruction, our nested attributes implementation just deletes immediately,
    # but having this simple method always returning false makes things work more compatibly
    # and smoothly with standard code for nested attributes deletion in form builders.
    def _destroy
      false
    end

    # like ActiveModel::Attributes at
    # https://github.com/rails/rails/blob/8015c2c2cf5c8718449677570f372ceb01318a32/activemodel/lib/active_model/attributes.rb#L120
    #
    # is not a full deep freeze
    def freeze
      attributes.freeze unless frozen?
      super
    end

    private

    def fill_in_defaults!
      self.class.attr_json_registry.definitions.each do |definition|
        if definition.has_default? && !attributes.has_key?(AttrJson.efficient_to_s(definition.name))
          self.send("#{definition.name.to_s}=", definition.provide_default!)
        end
      end
    end

    def _attr_json_write(key, value)
      if attribute_def = self.class.attr_json_registry[key.to_sym]
        attributes[AttrJson.efficient_to_s(key)] = attribute_def.cast(value)
      else
        # TODO, strict mode, ignore, raise, allow.
        attributes[AttrJson.efficient_to_s(key)] = value
      end
    end


    def _attr_json_write_unknown_attribute(key, value)
      case self.class.attr_json_config.unknown_key
      when :strip
        # drop it, no-op
      when :allow
        # just put it in the hash and let standard JSON casting have it
        _attr_json_write(key, value)
      else
        # default, :raise
        raise ActiveModel::UnknownAttributeError.new(self, key)
      end
    end

    # ActiveModel override.
    # Don't take from instance variables, take from the attributes
    # hash itself. Docs suggest we can override this for this very
    # use case: https://github.com/rails/rails/blob/e1e3be7c02acb0facbf81a97bbfe6d1a6e9ca598/activemodel/lib/active_model/serialization.rb#L152-L168
    def read_attribute_for_serialization(key)
      attributes[key]
    end
  end
end
