# frozen_string_literal: true

require 'attr_json/nested_attributes/multiparameter_attribute_writer'

module AttrJson
  module NestedAttributes
    # Implementation of `assign_nested_attributes` methods, called by the model
    # method of that name that {NestedAttributes} adds.
    class Writer
      attr_reader :model, :attr_name, :attr_def

      def initialize(model, attr_name)
        @model, @attr_name = model, attr_name
        @attr_def = model.class.attr_json_registry.fetch(attr_name)
      end

      delegate :nested_attributes_options, to: :model

      def assign_nested_attributes(attributes)
        if attr_def.array_of_primitive_type?
          assign_nested_attributes_for_primitive_array(attributes)
        elsif attr_def.array_type?
          assign_nested_attributes_for_model_array(attributes)
        else
          assign_nested_attributes_for_single_model(attributes)
        end
      end

      protected

      def model_send(method, *args)
        model.send(method, *args)
      end

      def unassignable_keys
       if model.class.const_defined?(:UNASSIGNABLE_KEYS)
        # https://github.com/rails/rails/blob/a45f234b028fd4dda5338e5073a3bf2b8bf2c6fd/activerecord/lib/active_record/nested_attributes.rb#L392
        (model.class)::UNASSIGNABLE_KEYS
        else
          # No need to mark "id" as unassignable in our AttrJson::Model-based nested models
          ["_destroy"]
        end
      end


      # Implementation for an `#{attribute_name}_attributes=` method, when the attr_json
      # attribute in question is recognized as an array of primitive values (not nested models)
      #
      # Really just exists to filter out blank/empty strings with reject_if.
      #
      # It will insist on filtering out empty strings and nils from arrays (ignores reject_if argument),
      # since that's the only reason to use it. It will respect limit argument.
      #
      # Filtering out empty strings can be convenient for using a hidden field in a form to
      # make sure an empty array gets set if all individual fields are removed from form using
      # cocoon-like javascript.
      def assign_nested_attributes_for_primitive_array(attributes_array)
        options = nested_attributes_options[attr_name]
        check_record_limit!(options[:limit], attributes_array)

        attributes_array = attributes_array.reject { |value| value.blank? }

        model_send("#{attr_name}=", attributes_array)
      end

      # Copied with signficant modifications from:
      # https://github.com/rails/rails/blob/master/activerecord/lib/active_record/nested_attributes.rb#L407
      def assign_nested_attributes_for_single_model(attributes)
        options = nested_attributes_options[attr_name]
        if attributes.respond_to?(:permitted?)
          attributes = attributes.to_h
        end
        attributes = attributes.with_indifferent_access

        existing_record = model_send(attr_name)

        if existing_record && has_destroy_flag?(attributes)
          # We don't have mark_for_destroy like in AR we just
          # set it to nil to eliminate it in the  AttrJson, that's it.
          model_send("#{attr_def.name}=", nil)

          return model
        end

        multi_parameter_attributes = extract_multi_parameter_attributes(attributes)

        if existing_record
          existing_record.assign_attributes(attributes.except(*unassignable_keys))
        elsif !reject_new_record?(attr_name, attributes)
          # doesn't exist yet, using the setter casting will build it for us
          # automatically.
          model_send("#{attr_name}=", attributes.except(*unassignable_keys))
        end

        if multi_parameter_attributes.present?
          MultiparameterAttributeWriter.new(
            model.send(attr_name)
          ).assign_multiparameter_attributes(multi_parameter_attributes)
        end

        return model
      end

      # Copied with significant modification from
      # https://github.com/rails/rails/blob/master/activerecord/lib/active_record/nested_attributes.rb#L466
      def assign_nested_attributes_for_model_array(attributes_collection)
        options = nested_attributes_options[attr_name]

        unless attributes_collection.is_a?(Hash) || attributes_collection.is_a?(Array)
          raise ArgumentError, "Hash or Array expected, got #{attributes_collection.class.name} (#{attributes_collection.inspect})"
        end

        check_record_limit!(options[:limit], attributes_collection)

        # Dunno what this is about but it's from ActiveRecord::NestedAttributes
        if attributes_collection.is_a? Hash
          keys = attributes_collection.keys
          attributes_collection = if keys.include?("id") || keys.include?(:id)
            [attributes_collection]
          else
            attributes_collection.values
          end
        end

        if attributes_collection.respond_to?(:permitted?)
          attributes_collection = attributes_collection.to_h
        end
        attributes_collection.collect!(&:stringify_keys)

        # remove ones marked with _destroy key, or rejected
        attributes_collection = attributes_collection.reject do |hash|
          hash.respond_to?(:[]) && (has_destroy_flag?(hash) || reject_new_record?(attr_name, hash))
        end

        attributes_collection.collect! { |h| h.except(*unassignable_keys) }

        multi_param_attr_array = attributes_collection.collect do |hash|
          extract_multi_parameter_attributes(hash)
        end

        # the magic of our type casting, this should 'just work', we'll have
        # a NEW array of models, unlike AR we don't re-use existing nested models
        # on assignment.
        model_send("#{attr_name}=", attributes_collection)

        multi_param_attr_array.each_with_index do |multi_param_attrs, i|
          unless multi_param_attrs.empty?
            MultiparameterAttributeWriter.new(
              model_send(attr_name)[i]
            ).assign_multiparameter_attributes(multi_param_attrs)
          end
        end

        return model
      end

      # Copied from ActiveRecord::NestedAttributes:
      #
      # Determines if a record with the particular +attributes+ should be
      # rejected by calling the reject_if Symbol or Proc (if defined).
      # The reject_if option is defined by +accepts_nested_attributes_for+.
      #
      # Returns false if there is a +destroy_flag+ on the attributes.
      def call_reject_if(association_name, attributes)
        return false if will_be_destroyed?(association_name, attributes)

        case callback = nested_attributes_options[association_name][:reject_if]
        when Symbol
          method(callback).arity == 0 ? send(callback) : send(callback, attributes)
        when Proc
          callback.call(attributes)
        end
      end

      # Copied from ActiveRecord::NestedAttributes unaltered.
      #
      # Determines if a hash contains a truthy _destroy key.
      def has_destroy_flag?(hash)
        ActiveModel::Type::Boolean.new.cast(hash["_destroy"])
      end

      # Copied from ActiveRecord::NestedAttributes
      #
      # Takes in a limit and checks if the attributes_collection has too many
      # records. It accepts limit in the form of symbol, proc, or
      # number-like object (anything that can be compared with an integer).
      #
      # Raises TooManyRecords error if the attributes_collection is
      # larger than the limit.
      def check_record_limit!(limit, attributes_collection)
        if limit
          limit = \
            case limit
            when Symbol
              model.send(limit)
            when Proc
              limit.call
            else
              limit
            end

          if limit && attributes_collection.size > limit
            raise ActiveRecord::NestedAttributes::TooManyRecords, "Maximum #{limit} records are allowed. Got #{attributes_collection.size} records instead."
          end
        end
      end

      # Copied from ActiveRecord::NestedAttributes
      #
      # Determines if a new record should be rejected by checking
      # has_destroy_flag? or if a <tt>:reject_if</tt> proc exists for this
      # association and evaluates to +true+.
      def reject_new_record?(association_name, attributes)
        will_be_destroyed?(association_name, attributes) || call_reject_if(association_name, attributes)
      end

      # Unlike ActiveRecord, we don't have an allow_destroy option, so
      # this is just `has_destroy_flag?`
      def will_be_destroyed?(association_name, attributes)
        has_destroy_flag?(attributes)
      end

      # mutates attributes passsed in to remove multiparameter attributes,
      # and returns multiparam in their own hash. Based on:
      # https://github.com/rails/rails/blob/42a16a4d6514f28e05f1c22a5f9125d194d9c7cb/activerecord/lib/active_record/attribute_assignment.rb#L15-L25
      # See AttrJson::NestedAttributes::MultiparameterAttributeWriter
      def extract_multi_parameter_attributes(attributes)
        multi_parameter_attributes  = {}

        attributes.each do |k, v|
          if k.include?("(")
            multi_parameter_attributes[k] = attributes.delete(k)
          end
        end

        return multi_parameter_attributes
      end
    end
  end
end
