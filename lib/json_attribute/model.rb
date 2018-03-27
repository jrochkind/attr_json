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
  #
  # You can control what happens if you set an unknown key (one that you didn't
  # register with `json_attribute`) with the class attribute `json_attribute_unknown_key`.
  # * :raise (default) raise ActiveModel::UnknownAttributeError
  # * :strip Ignore the unknown key and do not include it, without raising.
  # * :allow Allow the unknown key and it's value to be in the serialized hash,
  #     and written to the database. May be useful for legacy data or columns
  #     that other software touches, to let unknown keys just flow through.
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

      # :raise, :strip, :allow. :raise is default. Is there some way to enforce this.
      class_attribute :json_attribute_unknown_key
      self.json_attribute_unknown_key ||= :raise
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
            _json_attribute_write(name.to_s, value)
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
      if !attributes.respond_to?(:transform_keys)
        raise ArgumentError, "When assigning attributes, you must pass a hash as an argument."
      end

      super(self.class.fill_in_defaults(attributes))
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

      new_attributes.stringify_keys.each do |k, v|
        setter = :"#{k}="
        if respond_to?(setter)
          public_send(setter, v)
        else
          _json_attribute_write_unknown_attribute(k, v)
        end
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
        # Do we need unknown key handling here? Apparently not?
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

    # ActiveRecord objects [have a](https://github.com/rails/rails/blob/v5.1.5/activerecord/lib/active_record/nested_attributes.rb#L367-L374)
    # `_destroy`, related to `marked_for_destruction?` functionality used with AR nested attributes.
    # We don't mark for destruction, our nested attributes implementation just deletes immediately,
    # but having this simple method always returning false makes things work more compatibly
    # and smoothly with standard code for nested attributes deletion in form builders.
    def _destroy
      false
    end

    private

    def _json_attribute_write(key, value)
      if attribute_def = self.class.json_attributes_registry[key.to_sym]
        attributes[key.to_s] = attribute_def.cast(value)
      else
        # TODO, strict mode, ignore, raise, allow.
        attributes[key.to_s] = value
      end
    end


    def _json_attribute_write_unknown_attribute(key, value)
      case json_attribute_unknown_key
      when :strip
        # drop it, no-op
      when :allow
        # just put it in the hash and let standard JSON casting have it
        _json_attribute_write(key, value)
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
