module JsonAttribute
  module Record
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

            # TODO, do we really want to store this in the AR nested_attributes_options
            nested_attributes_options = self.nested_attributes_options.dup
            nested_attributes_options[attr_name.to_sym] = options
            self.nested_attributes_options = nested_attributes_options

            # We're generating into the same module normal AR nested attr setters
            # use, I think it's fine. You can't have a real association with the same
            # name as a `json_attribute`, that'd be all kinds of hurt anyway. If AR
            # changes it's stuff, it might hurt us though.
            _json_attributes_module.module_eval do
              if method_defined?(:"#{attr_name}_attributes=")
                remove_method(:"#{attr_name}_attributes=")
              end
              define_method "#{attr_name}_attributes=" do |attributes|
                ::JsonAttribute::Record::NestedAttributes::Writer.new(self, attr_name).assign_nested_attributes(attributes)
              end
            end

            if options[:define_build_method] != false
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
          @attr_def = model.class.json_attributes_registry[attr_name]
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
          (model.class)::UNASSIGNABLE_KEYS
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

        # Copied with significant modification from
        # https://github.com/rails/rails/blob/master/activerecord/lib/active_record/nested_attributes.rb#L466
        def assign_nested_attributes_for_model_array(attributes_collection)
          options = nested_attributes_options[attr_name]
          if attributes_collection.respond_to?(:permitted?)
            attributes_collection = attributes_collection.to_h
          end

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

          # remove ones marked with _destroy key, or rejected
          attributes_collection = attributes_collection.reject do |hash|
            hash.respond_to?(:[]) && (has_destroy_flag?(hash) || reject_new_record?(attr_name, hash))
          end

          # the magic of our type casting, this should 'just work', we'll have
          # a new array of models.
          model_send("#{attr_name}=", attributes_collection)
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
        # this is just...
        def will_be_destroyed?(association_name, attributes)
          has_destroy_flag?(attributes)
        end

      end
    end
  end
end
