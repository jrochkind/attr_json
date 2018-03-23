module JsonAttribute
  module Record
    # Add into an ActiveRecord object with JsonAttribute::Record,
    # to track dirty changes to json_attributes.
    module Dirty
      def json_attribute_changes
        Implementation.new(self)
      end


      class Implementation
        # The attribute_method stuff is copied from ActiveRecord::Dirty,
        # to give you all the same synthetic per-attribute methods.
        # We make it work with overridden #matched_attribute_method below.
        include ActiveModel::AttributeMethods

        # Attribute methods for "changed in last call to save?"
        attribute_method_affix(prefix: "saved_change_to_", suffix: "?")
        attribute_method_prefix("saved_change_to_")
        attribute_method_suffix("_before_last_save")

        # Attribute methods for "will change if I call save?"
        attribute_method_affix(prefix: "will_save_change_to_", suffix: "?")
        attribute_method_suffix("_change_to_be_saved", "_in_database")

        attr_reader :model

        def initialize(model, merged: false)
          @model = model
          @merged = !!merged
        end

        # return a copy with `merged` attribute true, so you can do things
        # like
        #     model.json_attribute_changes.merged.saved_change_to_attribute?(ordinary_or_json_attribute)
        def merged
          self.class.new(model, merged: true)
        end

        def merged?
          @merged
        end


        def saved_change_to_attribute(attr_name)
          attribute_def = registry.fetch(attr_name.to_sym)
          return nil unless attribute_def

          json_container = attribute_def.container_attribute

          (before_container, after_container) = model.saved_change_to_attribute(json_container)

          return nil if before_container.nil? && after_container.nil?

          before_v = before_container[attribute_def.store_key]
          after_v  = after_container[attribute_def.store_key]

          return nil if before_v.nil? && after_v.nil?

          [
            before_v,
            after_v
          ]
        end

        def attribute_before_last_save(attr_name)
          saved_change = saved_change_to_attribute(attr_name)
          return nil if saved_change.nil?

          saved_change[0]
        end

        def saved_change_to_attribute?(attr_name)
          ! saved_change_to_attribute(attr_name).nil?
        end

        def saved_changes
          saved_changes = model.saved_changes
          return {} if saved_changes == {}

          registry.definitions.collect do |definition|
            if container_change = saved_changes[definition.container_attribute]
              old_v = container_change[0][definition.store_key]
              new_v = container_change[1][definition.store_key]
              if old_v != new_v
                [
                  definition.name.to_s,
                  [
                    container_change[0][definition.store_key],
                    container_change[1][definition.store_key]
                  ]
                ]
              end
            end
          end.compact.to_h
        end

        def saved_changes?
          saved_changes.present?
        end


        def attribute_in_database(attr_name)
          to_be_saved = attribute_change_to_be_saved(attr_name)
          return nil if to_be_saved.nil?

          to_be_saved[0]
        end

        def attribute_change_to_be_saved(attr_name)
          attribute_def = registry.fetch(attr_name.to_sym)
          return nil unless attribute_def

          json_container = attribute_def.container_attribute

          (before_container, after_container) = model.attribute_change_to_be_saved(json_container)

          return nil if before_container.nil? && after_container.nil?

          before_v = before_container[attribute_def.store_key]
          after_v  = after_container[attribute_def.store_key]

          return nil if before_v.nil? && after_v.nil?

          [
            before_v,
            after_v
          ]
        end

        def will_save_change_to_attribute?(attr_name)
          ! attribute_change_to_be_saved(attr_name).nil?
        end

        def changes_to_save
          changes_to_save = model.changes_to_save
          return {} if changes_to_save == {}

          registry.definitions.collect do |definition|
            if container_change = changes_to_save[definition.container_attribute]
              old_v = container_change[0][definition.store_key]
              new_v = container_change[1][definition.store_key]
              if old_v != new_v
                [
                  definition.name.to_s,
                  [
                    old_v,
                    new_v
                  ]
                ]
              end
            end
          end.compact.to_h
        end

        def has_changes_to_save?
          changes_to_save.present?
        end

        def changed_attribute_names_to_save
          changes_to_save.keys
        end

        def attributes_in_database
          changes_to_save.transform_values(&:first)
        end

        private

        def registry
          model.class.json_attributes_registry
        end


        # Override from ActiveModel::AttributeMethods
        # to not require class-static define_attribute, but instead dynamically
        # find it from currently declared attributes.
        # https://github.com/rails/rails/blob/6aa5cf03ea8232180ffbbae4c130b051f813c670/activemodel/lib/active_model/attribute_methods.rb#L463-L468
        def matched_attribute_method(method_name)
          matches = self.class.send(:attribute_method_matchers_matching, method_name)
          matches.detect do |match|
            registry.attribute_registered?(match.attr_name)
          end
        end
      end
    end
  end
end
