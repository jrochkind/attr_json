require 'attr_json/nested_attributes/builder'
require 'attr_json/nested_attributes/writer'

module AttrJson
  # The implementation is based on ActiveRecord::NestedAttributes, from
  # https://github.com/rails/rails/blob/a45f234b028fd4dda5338e5073a3bf2b8bf2c6fd/activerecord/lib/active_record/nested_attributes.rb
  #
  # Re-used, and customized/overrode methods to match our implementation.
  # Copied over some implementation so we can use in ActiveModel's that original
  # isn't compatible with.
  # The original is pretty well put together and has had very low churn history.
  #
  #
  # Much of the AR implementation, copied, just works,
  # if we define `'#{attribute_name}_attributes='` methods that work. That's mostly what
  # we have to do here.
  #
  # Unlike AR, we try to put most of our implementation in seperate
  # implementation helper instances, instead of adding a bazillion methods to the model itself.
  module NestedAttributes
    extend ActiveSupport::Concern

    class_methods do
      # Much like ActiveRecord `accepts_nested_attributes_for`, but used with embedded
      # AttrJson::Model-type attributes (single or array). See doc page on Forms support.
      #
      # Note some AR options are _not_ supported.
      #
      # * _allow_destroy_, no such option. Effectively always true, doesn't make sense to try to gate this with our implementation.
      # * _update_only_, no such option. Not really relevant to this architecture where you're embedded models have no independent existence.
      #
      # If called on an array of 'primitive' (not AttrJson::Model) objects, it will do a kind of weird
      # thing where it creates an `#{attribute_name}_attributes=` method that does nothing
      # but filter out empty strings and nil values. This can be convenient in hackily form
      # handling array of primitives, see guide doc on forms.
      #
      # @overload attr_json_accepts_nested_attributes_for(define_build_method: true, reject_if: nil, limit: nil)
      #   @param define_build_method [Boolean] Default true, provide `build_attribute_name`
      #     method that works like you expect. [Cocoon](https://github.com/nathanvda/cocoon),
      #     for example, requires this. When true, you will get `model.build_#{attr_name}`
      #     methods. For array attributes, the attr_name will be singularized, as AR does.
      #   @param reject_if [Symbol,Proc] Allows you to specify a Proc or a Symbol pointing to a method
      #     that checks whether a record should be built for a certain attribute
      #     hash. Much like in AR accepts_nested_attributes_for.
      #   @param limit [Integer,Proc,Symbol] Allows you to specify the maximum number of associated records that
      #     can be processed with the nested attributes. Much like AR accepts_nested_attributes for.
      def attr_json_accepts_nested_attributes_for(*attr_names)
        options = { define_build_method: true }
        options.update(attr_names.extract_options!)
        options.assert_valid_keys(:reject_if, :limit, :define_build_method)
        options[:reject_if] = ActiveRecord::NestedAttributes::ClassMethods::REJECT_ALL_BLANK_PROC if options[:reject_if] == :all_blank

        unless respond_to?(:nested_attributes_options)
          # Add it when we're in a AttrJson::Model.  In an ActiveRecord::Base we'll just use the
          # existing one, it'll be okay.
          # https://github.com/rails/rails/blob/c14deceb9f36f82cd5ca3db214d85e1642eb0bfd/activerecord/lib/active_record/nested_attributes.rb#L16
          class_attribute :nested_attributes_options, instance_writer: false
          self.nested_attributes_options ||= {}
        end

        attr_names.each do |attr_name|
          attr_def = attr_json_registry[attr_name]

          unless attr_def
            raise ArgumentError, "No attr_json found for name '#{attr_name}'. Has it been defined yet?"
          end

          unless attr_def.array_type? || attr_def.single_model_type?
            raise TypeError, "attr_json_accepts_nested_attributes_for is only for array or nested model types; `#{attr_name}` is type #{attr_def.type.type.inspect}"
          end

          # We're sharing AR class attr in an AR, or using our own in a Model.
          nested_attributes_options = self.nested_attributes_options.dup
          nested_attributes_options[attr_name.to_sym] = options
          self.nested_attributes_options = nested_attributes_options

          _attr_jsons_module.module_eval do
            if method_defined?(:"#{attr_name}_attributes=")
              remove_method(:"#{attr_name}_attributes=")
            end
            define_method "#{attr_name}_attributes=" do |attributes|
              Writer.new(self, attr_name).assign_nested_attributes(attributes)
            end
          end

          # No build method for our wacky array of primitive type.
          if options[:define_build_method] && !attr_def.array_of_primitive_type?
            _attr_jsons_module.module_eval do
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
  end
end
