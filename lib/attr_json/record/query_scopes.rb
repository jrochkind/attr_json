require 'attr_json/record/query_builder'

module AttrJson
  module Record
    # Adds query-ing scopes into a AttrJson::Record, based
    # on postgres jsonb.
    #
    # Has to be mixed into something that also is a AttrJson::Record please!
    #
    # @example
    #      class MyRecord < ActiveRecord::Base
    #        include AttrJson::Record
    #        include AttrJson::Record::QueryScopes
    #
    #        attr_json :a_string, :string
    #      end
    #
    #      some_model.jsonb_contains(a_string: "foo").first
    #
    #      some_model.jsonb_contains_not(a_string: "bar").first
    #
    # See more in {file:README} docs.
    module QueryScopes
      extend ActiveSupport::Concern

      included do
        unless self < AttrJson::Record
          raise TypeError, "AttrJson::Record::QueryScopes can only be included in a AttrJson::Record"
        end

        scope(:jsonb_contains, lambda do |attributes|
          QueryBuilder.new(self, attributes).contains_relation
        end)

        scope(:jsonb_contains_not, lambda do |attributes|
          QueryBuilder.new(self, attributes).contains_not_relation
        end)
      end
    end
  end
end
