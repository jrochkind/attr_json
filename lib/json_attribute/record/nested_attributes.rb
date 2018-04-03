module JsonAttribute
  module Record
    # The implementation is copied and modified from ActiveRecord::NestedAttributes.
    #
    # We have to change reflection methods for telling whether something is to-one or
    # to-many, and implementations of destoying and ids and such.
    #
    # But much of the AR implementation, including form builder stuff, just works,
    # if we define `#{attribute_name}_attributes=` methods that work. That's mostly what
    # we have to do here.
    #
    # since the AR implementation hasn't changed substantially in years, hopefully
    # it won't start doing so and make us out of sync.
    #
    # Unlike AR, we try to put most of our implementation in a seperate
    # Implementation instance, instead of adding a bazillion methods to the model itself.
    #
    # NOTES: eliminated 'update_only' option, not applicable (I think)
    module NestedAttributes
      extend ActiveSupport::Concern

      class_methods do
        def json_attribute_accepts_nested_attributes_for(*attr_names)
          options = { allow_destroy: false }
          options.update(attr_names.extract_options!)
          options.assert_valid_keys(:allow_destroy, :reject_if, :limit)
          options[:reject_if] = REJECT_ALL_BLANK_PROC if options[:reject_if] == :all_blank

          attr_names.each do |attr_name|
            if attr_def = json_attributes_registry[attr_name]
              # TODO, do we really want to store this in the AR nested_attributes_options
              nested_attributes_options = self.nested_attributes_options.dup
              nested_attributes_options[attr_name.to_sym] = options
              self.nested_attributes_options = nested_attributes_options

              # We're generating into the same module normal AR nested attr setters
              # use, I think it's fine. You can't have a real association with the same
              # name as a `json_attribute`, that'd be all kinds of hurt anyway. If AR
              # changes it's stuff, it might hurt us though.
              generated_association_methods.module_eval <<-eoruby, __FILE__, __LINE__ + 1
                if method_defined?(:#{attr_name}_attributes=)
                  remove_method(:#{attr_name}_attributes=)
                end
                def #{attr_name}_attributes=(attributes)
                  ::JsonAttribute::Record::NestedAttributes::Writer.new(self, :#{attr_name}).assign_nested_attributes(attributes)
                end
              eoruby
            else
              raise ArgumentError, "No json_attribute found for name `#{attr_name}'. Has it been defined yet?"
            end
          end
        end
      end

      class Writer
        attr_reader :model, :attr_name, :attr_def

        # We can totally use the methods from ActiveRecord::NestedAttributes.
        # Is this a bad idea? I dunno.
        #
        # Using this custom imp instead of ActiveSupport `delegate` so
        # we can send to private method in model.
        [ :nested_attributes_options, :call_reject_if, :allow_destroy?,
          :reject_new_record?, :has_destroy_flag?, :check_record_limit!
        ].each do |method|
          define_method(method) do |*args|
            model.send(method, *args)
          end
          private :method
        end

        def initialize(model, attr_name)
          @model = model
          @attr_name = attr_name
          @attr_def = model.class.json_attributes_registry[attr_name]

          # TODO, we should be able to ask attr_def.array?
          @is_array_type = !!attr_def.type.is_a?(JsonAttribute::Type::Array)
        end

        def is_array_type?
          @is_array_type
        end

        def model_send(method, *args)
          model.send(method, *args)
        end

        def unassignable_keys
          (model.class)::UNASSIGNABLE_KEYS
        end

        def assign_nested_attributes(attributes)
          if is_array_type?
            assign_nested_attributes_for_model_array(attributes)
          else
            assign_nested_attributes_for_single_model(attributes)
          end
        end

        # Based on and much like AR's `assign_nested_attributes_for_one_to_one_association`,
        # but much simpler.
        def assign_nested_attributes_for_single_model(attributes)
          options = nested_attributes_options[attr_name]
          if attributes.respond_to?(:permitted?)
            attributes = attributes.to_h
          end
          attributes = attributes.with_indifferent_access

          existing_record = model_send(attr_name)

          if existing_record && has_destroy_flag?(attributes) && allow_destroy?(attr_name)
            # we just delete it right away, not mark_for_destroy like in AR, hopefully
            # that'll work out.
            # setting it to nil will eliminate it in JsonAttribute, that's it.
            model_send("#{attr_def.name}=", nil)
          elsif existing_record
            existing_record.assign_attributes(attributes.except(*unassignable_keys))
          elsif !reject_new_record?(attr_name, attributes)
            # doesn't exist yet, using the setter casting will build it for us
            # automatically.
            send("#{attr_name}=", attributes)
          end
        end

        def assign_nested_attributes_for_model_array(attributes_collection)
          options = nested_attributes_options[attr_name]
          if attributes_collection.respond_to?(:permitted?)
            attributes_collection = attributes_collection.to_h
          end

          unless attributes_collection.is_a?(Hash) || attributes_collection.is_a?(Array)
            raise ArgumentError, "Hash or Array expected, got #{attributes_collection.class.name} (#{attributes_collection.inspect})"
          end

          check_record_limit!(options[:limit], attributes_collection)

          if attributes_collection.is_a? Hash
            keys = attributes_collection.keys
            attributes_collection = if keys.include?("id") || keys.include?(:id)
              [attributes_collection]
            else
              attributes_collection.values
            end
          end

          if allow_destroy?(attr_name)
            # remove ones marked with _destroy key
            attributes_collection = attributes_collection.reject do |hash|
              hash.respond_to?(:[]) && has_destroy_flag?(hash)
            end
          end

          # the magic of our type casting, this should 'just work'?
          model_send("#{attr_name}=", attributes_collection)
        end
      end
    end
  end
end
