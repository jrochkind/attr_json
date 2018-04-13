require 'json_attribute/nested_attributes/builder'
require 'json_attribute/nested_attributes/writer'

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
  end
end
