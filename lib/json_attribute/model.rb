require 'active_support/concern'
require 'active_model/type'

require 'json_attribute/attribute_definition'
require 'json_attribute/attribute_definition/registry'

require 'json_attribute/type/model'

module JsonAttribute

  # Meant for use in a plain class, turns it into an ActiveModel::Model
  # with json_attribute support. NOT for use in an ActiveRecord::Base model,
  # see `Record` for ActiveRecord use.
  #
  # Creates an ActiveModel object with _typed_ attributes, easily serializable
  # to json, and with a corresponding ActiveModel::Type representing the class.
  # Meant for use as an attribute of a JsonAttribute::Record. Can be nested,
  # JsonAttribute::Models can have attributes that are other JsonAttribute::Models.
  #
  # Includes ActiveModel::Model whether you like it or not. TODO, should it?
  module Model
    extend ActiveSupport::Concern

    include ActiveModel::Model
    include ActiveModel::Serialization
    #include ActiveModel::Dirty

    included do
      if self < ActiveRecord::Base
        raise TypeError, "JsonAttribute::Model is not for an ActiveRecord::Base model. #{self} appears to be one. Are you looking for ::JsonAttribute::Record?"
      end

      class_attribute :json_attributes_registry, instance_accessor: false
      self.json_attributes_registry = ::JsonAttribute::AttributeDefinition::Registry.new
    end

    class_methods do
      # Like `.new`, but translate store keys in hash
      def new_from_serializable(attributes = {})
        attributes = attributes.transform_keys do |key|
          # store keys in arguments get translated to attribute names on initialize.
          if attribute_def = self.json_attributes_registry.store_key_lookup("", key.to_s)
            attribute_def.name.to_s
          else
            key
          end
        end
        self.new(attributes)
      end

      def to_type
        @type ||= JsonAttribute::Type::Model.new(self)
      end

      # Type can be an instance of an ActiveModel::Type::Value subclass, or a symbol that will
      # be looked up in `ActiveModel::Type.lookup`
      # TODO doc options
      def json_attribute(name, type, **options)
        self.json_attributes_registry = json_attributes_registry.with(
          AttributeDefinition.new(name.to_sym, type, options)
        )

        # By default, automatically validate nested models
        if type.kind_of?(JsonAttribute::Type::Model) && options[:validate] != false
          # Yes. we're passing an ActiveRecord::Validations validator, but
          # it works fine for ActiveModel. If this changes in the future, tests will catch.
          self.validates_with ActiveRecord::Validations::AssociatedValidator, attributes: [name.to_sym]
        end

        _json_attributes_module.module_eval do
          define_method("#{name}=") do |value|
            write_json_attribute(name.to_s, value)
          end

          define_method("#{name}") do
            attributes[name.to_s]
          end
        end
      end

      # This should kind of be considered 'protected', but the semantics
      # of how we want to call it don't give us a visibility modifier that works.
      # Prob means refactoring called for. TODO?
      def fill_in_defaults(hash)
        # Only if we need to mutate it to add defaults, we'll dup it first. deep_dup not neccesary
        # since we're only modifying top-level here.
        duped = false
        json_attributes_registry.definitions.each do |definition|
          if definition.has_default? && ! (hash.has_key?(definition.store_key.to_s) || hash.has_key?(definition.store_key.to_sym))
            unless duped
              hash = hash.dup
              duped = true
            end

            hash[definition.store_key] = definition.provide_default!
          end
        end

        hash
      end

      private

      # Define an anonymous module and include it, so can still be easily
      # overridden by concrete class. Design cribbed from ActiveRecord::Store
      # https://github.com/rails/rails/blob/4590d7729e241cb7f66e018a2a9759cb3baa36e5/activerecord/lib/active_record/store.rb
      def _json_attributes_module # :nodoc:
        @_json_attributes_module ||= begin
          mod = Module.new
          include mod
          mod
        end
      end
    end

    def initialize(attributes = {})
      # TODO, move this all/some to #assign_attributes, so we get store key translation
      # on assign_attributes. And defaults fill-in, is that appropriate on assign_attributes?
      # test ActiveRecord objects and see.
      if !attributes.respond_to?(:transform_keys)
        raise ArgumentError, "When assigning attributes, you must pass a hash as an argument."
      end

      attributes = self.class.fill_in_defaults(attributes)
      super(attributes)
    end

    def attributes
      @attributes ||= {}
    end

    def attributes=(hash)
      #TODO should this be casting? maybe not, you can always set
      # attiributes[:foo]= without casting anyway. it'll get casted
      # on #serializable_hash. Hmm, but i'm leaning toward it should cast TODO.
      @attributes = hash
    end

    def write_json_attribute(key, value)
      if attribute_def = self.class.json_attributes_registry[key.to_sym]
        attributes[key.to_s] = attribute_def.cast(value)
      else
        # TODO, strict mode, ignore, raise, allow.
        attributes[key.to_s] = value
      end
    end

    # Override from ActiveModel::Serialization to #serialize
    # by type to make sure any values set directly on hash still
    # get properly type-serialized.
    def serializable_hash(*options)
      super.collect do |key, value|
        if attribute_def = self.class.json_attributes_registry[key.to_sym]
          key = attribute_def.store_key
          if value.kind_of?(Time) || value.kind_of?(DateTime)
            value = value.utc.change(usec: 0)
          end

          value = attribute_def.serialize(value)
        end

        # TODO strict key stuff?

        [key, value]
      end.to_h
    end

    # ActiveRecord JSON serialization will insist on calling
    # this, instead of the specified type's #serialize, at least in some cases.
    # So it's important we define it -- the default #as_json added by ActiveSupport
    # will serialize all instance variables, which is not what we want.
    def as_json(*options)
      serializable_hash(*options)
    end

    # We deep_dup on #to_h, you want attributes unduped, ask for #attributes.
    def to_h
      attributes.deep_dup
    end

    # Two JsonAttribute::Model objects are equal if they are the same class
    # or one is a subclass of the other, AND their #attributes are equal.
    # TODO: Should we allow subclasses to be equal, or should they have to be the
    # exact same class?
    def ==(other_object)
      (other_object.is_a?(self.class) || self.is_a?(other_object.class)) &&
      other_object.attributes == self.attributes
    end

    private

    # Don't take from instance variables, take from the attributes
    # hash itself. Docs suggest we can override this for this very
    # use case: https://github.com/rails/rails/blob/e1e3be7c02acb0facbf81a97bbfe6d1a6e9ca598/activemodel/lib/active_model/serialization.rb#L152-L168
    def read_attribute_for_serialization(key)
      attributes[key]
    end

    # Override to just set in hash. We are overriding a private method,
    # and docs don't really say we can as part of intended API -- but how
    # else to get the counterpart to `read_attribute_for_serialization`
    # that docs do say you can override?  If needed, we could override all of assign_attributes
    # or something, I guess?
    #
    # WARNING: using possibly non-public Rails API
    #
    # TODO: Should this raise on attributes not allowed as json_attribute?
    # for now we let everything in. It IS still protected by
    # ForbiddenAttributesProtection in default `assign_attributes` (test?)
    # Maybe we want a 'strict_attributes' option. And/or option that
    # throws out rather than raises on non defined attributes?
    def _assign_attribute(k, v)
      write_json_attribute(k, v)
    end
  end
end
