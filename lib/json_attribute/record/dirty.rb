module JsonAttribute
  module Record
    # Add into an ActiveRecord object with JsonAttribute::Record,
    # to track dirty changes to json_attributes.
    #
    #    some_model.json_attribute_changes.saved_changes
    #    some_model.json_attribute_changes.json_attr_before_last_save
    #
    # By default, it _only_ includes changes from json attributes.
    # To have a merged list also including ordinary AR changes, add on `merged`:
    #
    #    some_model.json_attribute_changes.merged.saved_changes
    #    some_model.json_attribute_changes.merged.ordinary_attr_before_last_save
    #
    # Complex nested models will show up in changes as the cast models. If you want
    # the raw json instead, use `as_json`:
    #
    #    some_model.json_attribute_changes.as_json.saved_changes
    #
    # You can combine as_json and merged if you like:
    #
    #    some_model.json_attribute_changes.as_json.merged.saved_changes
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

        def initialize(model, merged: false, merge_containers: false, as_json: false)
          @model = model
          @merged = !!merged
          @merge_containers = !!merge_containers
          @as_json = !!as_json
        end

        # return a copy with `merged` attribute true, so dirty tracking
        # will include ordinary AR attributes too, and you can do things like:
        #
        #     model.json_attribute_changes.merged.saved_change_to_attribute?(ordinary_or_json_attribute)
        #
        # By default, the json container attributes are included too. If you
        # instead want our dirty tracking to pretend they don't exist:
        #
        #     model.json_attribute_changes.merged(containers: false).etc
        #
        def merged(containers: true)
          self.class.new(model, merged: true, merge_containers: containers,
            as_json: as_json?)
        end

        # return a copy with as_json parameter set to true, so change diffs
        # will be the json structures serialized, not the cast models.
        # for 'primitive' types will be the same, but for JsonAttribute::Models
        # very different.
        def as_json
          self.class.new(model, as_json: true,
            merged: merged?,
            merge_containers: merge_containers?)
        end

        # should we handle ordinary AR attributes too in one merged
        # change tracker?
        def merged?
          @merged
        end

        # if we're `merged?` and `merge_containers?` is **false**, we
        # _omit_ our json container attributes from our dirty tracking.
        # only has meaning if `merged?` is true. Defaults to true.
        def merge_containers?
          @merge_containers
        end

        def as_json?
          @as_json
        end


        def saved_change_to_attribute(attr_name)
          attribute_def = registry[attr_name.to_sym]
          if ! attribute_def
            if merged? && (merge_containers? || ! registry.container_attributes.include?(attr_name.to_s))
              return model.saved_change_to_attribute(attr_name)
            else
              return nil
            end
          end

          json_container = attribute_def.container_attribute

          (before_container, after_container) = model.saved_change_to_attribute(json_container)

          return nil if before_container.nil? && after_container.nil?

          before_v = before_container[attribute_def.store_key]
          after_v  = after_container[attribute_def.store_key]

          return nil if before_v.nil? && after_v.nil?

          if as_json?
            before_v = attribute_def.type.serialize(before_v) unless before_v.nil?
            after_v = attribute_def.type.serialize(after_v) unless after_v.nil?
          end

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
          return nil unless registry[attr_name.to_sym] || merged? && (merge_containers? || ! registry.container_attributes.include?(attr_name.to_s))
          ! saved_change_to_attribute(attr_name).nil?
        end

        def saved_changes
          saved_changes = model.saved_changes
          return {} if saved_changes == {}

          json_attr_changes = registry.definitions.collect do |definition|
            if container_change = saved_changes[definition.container_attribute]
              old_v = container_change[0][definition.store_key]
              new_v = container_change[1][definition.store_key]
              if old_v != new_v
               if as_json?
                 old_v = definition.type.serialize(old_v) unless old_v.nil?
                 new_v = definition.type.serialize(new_v) unless new_v.nil?
               end

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

          if merged?
            saved_changes.merge(json_attr_changes).tap do |merged|
              unless merge_containers?
                merged.except!(*registry.container_attributes)
              end
            end
          else
            json_attr_changes
          end
        end

        def saved_changes?
          saved_changes.present?
        end


        def attribute_in_database(attr_name)
          to_be_saved = attribute_change_to_be_saved(attr_name)
          if to_be_saved.nil?
            if merged? && (merge_containers? || ! registry.container_attributes.include?(attr_name.to_s))
              return model.attribute_change_to_be_saved(attr_name)
            else
              return nil
            end
          end

          to_be_saved[0]
        end

        def attribute_change_to_be_saved(attr_name)
          attribute_def = registry[attr_name.to_sym]
          if ! attribute_def
            if merged? && (merge_containers? || ! registry.container_attributes.include?(attr_name.to_s))
              return model.attribute_change_to_be_saved(attr_name)
            else
              return nil
            end
          end

          json_container = attribute_def.container_attribute

          (before_container, after_container) = model.attribute_change_to_be_saved(json_container)

          return nil if before_container.nil? && after_container.nil?

          before_v = before_container[attribute_def.store_key]
          after_v  = after_container[attribute_def.store_key]

          return nil if before_v.nil? && after_v.nil?

         if as_json?
           before_v = attribute_def.type.serialize(before_v) unless before_v.nil?
           after_v = attribute_def.type.serialize(after_v) unless after_v.nil?
         end

          [
            before_v,
            after_v
          ]
        end

        def will_save_change_to_attribute?(attr_name)
          return nil unless registry[attr_name.to_sym] || merged? && (merge_containers? || ! registry.container_attributes.include?(attr_name.to_s))
          ! attribute_change_to_be_saved(attr_name).nil?
        end

        def changes_to_save
          changes_to_save = model.changes_to_save

          return {} if changes_to_save == {}

          json_attr_changes = registry.definitions.collect do |definition|
            if container_change = changes_to_save[definition.container_attribute]
              old_v = container_change[0][definition.store_key]
              new_v = container_change[1][definition.store_key]
              if old_v != new_v
                if as_json?
                  old_v = definition.type.serialize(old_v) unless old_v.nil?
                  new_v = definition.type.serialize(new_v) unless new_v.nil?
                end

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

          if merged?
            changes_to_save.merge(json_attr_changes).tap do |merged|
              unless merge_containers?
                merged.except!(*registry.container_attributes)
              end
            end
          else
            json_attr_changes
          end
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
