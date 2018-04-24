require 'json_attribute/record/query_builder'

module JsonAttribute
  module Record
    # Adds query-ing scopes into a JsonAttribute::Record, based
    # on postgres jsonb.
    #
    # Has to be mixed into something that also is a JsonAttribute::Record please!
    #
    # @example
    #      class MyRecord < ActiveRecord::Base
    #        include JsonAttribute::Record
    #        include JsonAttribute::Record::QueryScopes
    #
    #        json_attribute :a_string, :string
    #      end
    #
    #      some_model.jsonb_contains(a_string: "foo").first
    #
    # See more in {file:README} docs.
    module QueryScopes
      extend ActiveSupport::Concern

      included do
        unless self < JsonAttribute::Record
          raise TypeError, "JsonAttribute::Record::QueryScopes can only be included in a JsonAttribute::Record"
        end

        scope(:jsonb_contains, lambda do |attributes|
          QueryBuilder.new(self, attributes).contains_relation
        end)
      end
    end
  end
end
