require 'json_attribute/record/query_builder'

module JsonAttribute
  module Record
    # Adds query-ing scopes into a JsonAttribute::Record, based
    # on postgres jsonb.
    #
    # Has to be mixed into something that also is a JsonAttribute::Record please!
    module QueryScopes
      extend ActiveSupport::Concern

      included do
        scope(:jsonb_contains, lambda do |attributes|
          QueryBuilder.new(self, attributes).contains_relation
        end)
      end
    end
  end
end
