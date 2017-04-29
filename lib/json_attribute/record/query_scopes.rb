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
          attributes = attributes.collect do |key, value|
            attr_def = json_attributes_registry[key.to_sym]

            [attr_def.store_key, attr_def.serialize(attr_def.cast value)]
          end.to_h
          where("#{table_name}.json_attributes @> (?)::jsonb", attributes.to_json)
        end)
      end
    end
  end
end
