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
          options = {  }
          options.update(attr_names.extract_options!)
          options.assert_valid_keys(:reject_if, :limit)
          options[:reject_if] = ActiveRecord::NestedAttributes::ClassMethods::REJECT_ALL_BLANK_PROC if options[:reject_if] == :all_blank

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

              if options[:define_build_method] != false
                build_method_name = "build_#{attr_name.to_s.singularize}"

                generated_association_methods.module_eval do
                  if method_defined?(build_method_name)
                    remove_method(build_method_name)
                  end
                  define_method build_method_name do |params = {}|
                    Builder.new(self, attr_name).build(params)
                  end
                end
              end
            else
              raise ArgumentError, "No json_attribute found for name '#{attr_name}'. Has it been defined yet?"
            end
          end
        end
      end

      class Builder
        attr_reader :model, :attr_name, :attr_def

        def initialize(model, attr_name)
          @model = model
          @attr_name = attr_name
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

        # We can totally use the methods from ActiveRecord::NestedAttributes.
        # Is this a bad idea? I dunno.
        #
        # Using this custom imp instead of ActiveSupport `delegate` so
        # we can send to private method in model.
        [ :nested_attributes_options, :call_reject_if,
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
        end

        def model_send(method, *args)
          model.send(method, *args)
        end

        def unassignable_keys
          (model.class)::UNASSIGNABLE_KEYS
        end

        def assign_nested_attributes(attributes)
          if attr_def.array_type?
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

          if existing_record && has_destroy_flag?(attributes)
            # we just delete it right away, not mark_for_destroy like in AR, hopefully
            # that'll work out.
            # setting it to nil will eliminate it in JsonAttribute, that's it.
            model_send("#{attr_def.name}=", nil)
          elsif existing_record
            existing_record.assign_attributes(attributes.except(*unassignable_keys))
          elsif !reject_new_record?(attr_name, attributes)
            # doesn't exist yet, using the setter casting will build it for us
            # automatically.
            model_send("#{attr_name}=", attributes)
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

          # remove ones marked with _destroy key, or rejected
          attributes_collection = attributes_collection.reject do |hash|
            hash.respond_to?(:[]) && (has_destroy_flag?(hash) || reject_new_record?(attr_name, hash))
          end

          # the magic of our type casting, this should 'just work'?
          model_send("#{attr_name}=", attributes_collection)
        end
      end
    end
  end
end
