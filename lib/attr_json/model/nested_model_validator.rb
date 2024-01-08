module AttrJson
  module Model
    # Used to validate an attribute in an AttrJson::Model whose values are other models, when
    # you want validation errors on the nested models to post up.
    #
    # This is based on ActiveRecord's own ActiveRecord::Validations::AssociatedValidator, and actually forked
    # from it at https://github.com/rails/rails/blob/e37adfed4eff3b43350ec87222a922e9c72d9c1b/activerecord/lib/active_record/validations/associated.rb
    #
    # We used to simply use an ActiveRecord::Validations::AssociatedValidator, but as of https://github.com/jrochkind/attr_json/pull/220 (e1e798142d)
    # it got ActiveRecord-specific functionality that no longer worked with our use case.
    #
    # No problem, the implementation is simple, we can provide it here, based on the last version that did work.
    class NestedModelValidator < ActiveModel::EachValidator
      def validate_each(record, attribute, value)
        if Array(value).reject { |r| valid_object?(r) }.any?
          record.errors.add(attribute, :invalid, **options.merge(value: value))
        end
      end

      private
        def valid_object?(record)
          #(record.respond_to?(:marked_for_destruction?) && record.marked_for_destruction?) || record.valid?
          record.valid?
        end
    end
  end
end
