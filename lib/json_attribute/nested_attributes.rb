module JsonAttribute
  # The implementation is based on ActiveRecord::NestedAttributes, from
  # https://github.com/rails/rails/blob/a45f234b028fd4dda5338e5073a3bf2b8bf2c6fd/activerecord/lib/active_record/nested_attributes.rb
  #
  # Re-used, and customized/overrode methods to match our implementation.
  # Copied over some implementation so we can use in ActiveModel's that original
  # isn't compatible with.
  # The original is pretty well put together and has had very low churn history.
  #
  #
  # But much of the AR implementation, including form builder stuff, just works,
  # if we define `#{attribute_name}_attributes=` methods that work. That's mostly what
  # we have to do here.
  #
  # Unlike AR, we try to put most of our implementation in seperate
  # Implementation instances, instead of adding a bazillion methods to the model itself.
  #
  # NOTES: eliminated 'update_only' option, not applicable (I think). Eliminated allow_destroy,
  # doesn't make sense, it's always allowed, as they could do the same just by eliminating
  # the row from the submitted params.
  module NestedAttributes
    extend ActiveSupport::Concern

    class_methods do
      # @param define_build_method [Boolean] (keyword) Default true, provide `build_attribute_name`
      #    method that works like you expect. [Cocoon](https://github.com/nathanvda/cocoon),
      #    for example, requires this.
      def json_attribute_accepts_nested_attributes_for(*attr_names)
        options = { define_build_method: true }
        options.update(attr_names.extract_options!)
        options.assert_valid_keys(:reject_if, :limit, :define_build_method)
        options[:reject_if] = ActiveRecord::NestedAttributes::ClassMethods::REJECT_ALL_BLANK_PROC if options[:reject_if] == :all_blank

        unless respond_to?(:nested_attributes_options)
          # Add it when we're in a JsonAttribute::Model.  In an ActiveRecord::Base we'll just use the
          # existing one, it'll be okay.
          # https://github.com/rails/rails/blob/c14deceb9f36f82cd5ca3db214d85e1642eb0bfd/activerecord/lib/active_record/nested_attributes.rb#L16
          class_attribute :nested_attributes_options, instance_writer: false
          self.nested_attributes_options ||= {}
        end

        attr_names.each do |attr_name|
          attr_def = json_attributes_registry[attr_name]

          unless attr_def
            raise ArgumentError, "No json_attribute found for name '#{attr_name}'. Has it been defined yet?"
          end

          # We're sharing AR class attr in an AR, or using our own in a Model.
          nested_attributes_options = self.nested_attributes_options.dup
          nested_attributes_options[attr_name.to_sym] = options
          self.nested_attributes_options = nested_attributes_options

          _json_attributes_module.module_eval do
            if method_defined?(:"#{attr_name}_attributes=")
              remove_method(:"#{attr_name}_attributes=")
            end
            define_method "#{attr_name}_attributes=" do |attributes|
              Writer.new(self, attr_name).assign_nested_attributes(attributes)
            end
          end

          if options[:define_build_method]
            _json_attributes_module.module_eval do
              build_method_name = "build_#{attr_name.to_s.singularize}"
              if method_defined?(build_method_name)
                remove_method(build_method_name)
              end
              define_method build_method_name do |params = {}|
                Builder.new(self, attr_name).build(params)
              end
            end
          end
        end
      end
    end

    class Builder
      attr_reader :model, :attr_name, :attr_def

      def initialize(model, attr_name)
        @model, @attr_name = model, attr_name,
        @attr_def = model.class.json_attributes_registry[attr_name]
      end

      def build(params = {})
        if attr_def.array_type?
          model.send("#{attr_name}=", (model.send(attr_name) || []) + [params])
          return model.send("#{attr_name}").last
        else
          model.send("#{attr_name}=", params)
          return model.send("#{attr_name}")
        end
      end
    end

    class Writer
      attr_reader :model, :attr_name, :attr_def

      def initialize(model, attr_name)
        @model, @attr_name = model, attr_name
        @attr_def = model.class.json_attributes_registry.fetch(attr_name)
      end

      delegate :nested_attributes_options, to: :model

      def assign_nested_attributes(attributes)
        if attr_def.array_type?
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
          # No need to mark "id" as unassignable in our JsonAttribute::Model-based nested models
          ["_destroy"]
        end
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
          # set it to nil to eliminate it in the  JsonAttribute, that's it.
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
      # See JsonAttribute::NestedAttributes::MultiparameterAttributeWriter
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

    # Rails has a weird "multiparameter attribute" thing, that is used for simple_form's
    # date/time html entry (datetime may be ALL it's ever been used for in Rails!),
    # using weird parameters in the HTTP query params like "dateattribute(2i)".
    # It is weird code, and I do NOT really understand the implementation, but it's also
    # very low-churn, hasn't changed much in recent Rails history.
    #
    # In Rails at present it's only on ActiveRecord, we need it used on our JsonAttribute::Models
    # too, so we copy and paste extract it here, from:
    # https://github.com/rails/rails/blob/42a16a4d6514f28e05f1c22a5f9125d194d9c7cb/activerecord/lib/active_record/attribute_assignment.rb
    #
    # We only use it in our "#{attr_name}_attriubtes=" methods, that's enough to
    # get what we need for support of this stuff in our stuff, for form submisisons
    # using rails-style date/time inputs as used eg in simple_form. And then we don't
    # need to polute anything outside of NestedAttributes module with this crazy stuff.
    class MultiparameterAttributeWriter
      attr_reader :model
      def initialize(model)
        @model = model
      end

      # Copied from Rails. https://github.com/rails/rails/blob/42a16a4d6514f28e05f1c22a5f9125d194d9c7cb/activerecord/lib/active_record/attribute_assignment.rb#L39
      #
      # Instantiates objects for all attribute classes that needs more than one constructor parameter. This is done
      # by calling new on the column type or aggregation type (through composed_of) object with these parameters.
      # So having the pairs written_on(1) = "2004", written_on(2) = "6", written_on(3) = "24", will instantiate
      # written_on (a date type) with Date.new("2004", "6", "24"). You can also specify a typecast character in the
      # parentheses to have the parameters typecasted before they're used in the constructor. Use i for Integer and
      # f for Float. If all the values for a given attribute are empty, the attribute will be set to +nil+.
      def assign_multiparameter_attributes(pairs)
        execute_callstack_for_multiparameter_attributes(
          extract_callstack_for_multiparameter_attributes(pairs)
        )
      end

      protected

      # copied from Rails https://github.com/rails/rails/blob/42a16a4d6514f28e05f1c22a5f9125d194d9c7cb/activerecord/lib/active_record/attribute_assignment.rb#L45
      def execute_callstack_for_multiparameter_attributes(callstack)
        errors = []
        callstack.each do |name, values_with_empty_parameters|
          begin
            if values_with_empty_parameters.each_value.all?(&:nil?)
              values = nil
            else
              values = values_with_empty_parameters
            end
            model.send("#{name}=", values)
          rescue => ex
            errors << ActiveRecord::AttributeAssignmentError.new("error on assignment #{values_with_empty_parameters.values.inspect} to #{name} (#{ex.message})", ex, name)
          end
        end
        unless errors.empty?
          error_descriptions = errors.map(&:message).join(",")
          raise ActiveRecord::MultiparameterAssignmentErrors.new(errors), "#{errors.size} error(s) on assignment of multiparameter attributes [#{error_descriptions}]"
        end
      end

      # copied from Rails https://github.com/rails/rails/blob/42a16a4d6514f28e05f1c22a5f9125d194d9c7cb/activerecord/lib/active_record/attribute_assignment.rb#L65
      def extract_callstack_for_multiparameter_attributes(pairs)
        attributes = {}

        pairs.each do |(multiparameter_name, value)|
          attribute_name = multiparameter_name.split("(").first
          attributes[attribute_name] ||= {}

          parameter_value = value.empty? ? nil : type_cast_attribute_value(multiparameter_name, value)
          attributes[attribute_name][find_parameter_position(multiparameter_name)] ||= parameter_value
        end

        attributes
      end

      # copied from Rails https://github.com/rails/rails/blob/42a16a4d6514f28e05f1c22a5f9125d194d9c7cb/activerecord/lib/active_record/attribute_assignment.rb#L79
      def type_cast_attribute_value(multiparameter_name, value)
        multiparameter_name =~ /\([0-9]*([if])\)/ ? value.send("to_" + $1) : value
      end

      # copied from Rails https://github.com/rails/rails/blob/42a16a4d6514f28e05f1c22a5f9125d194d9c7cb/activerecord/lib/active_record/attribute_assignment.rb#L83
      def find_parameter_position(multiparameter_name)
        multiparameter_name.scan(/\(([0-9]*).*\)/).first.first.to_i
      end
    end
  end
end
