module JsonAttribute
  module NestedAttributes
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
