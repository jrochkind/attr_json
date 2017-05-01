module JsonAttribute
  module Record
    class QueryBuilder
      attr_reader :relation, :input_attributes
      def initialize(relation, input_attributes)
        @relation = relation
        @input_attributes = input_attributes
      end

      def contains_relation
        attributes = input_attributes.collect do |key, value|
          attr_def = relation.json_attributes_registry[key.to_sym]

          [attr_def.store_key, attr_def.serialize(attr_def.cast value)]
        end.to_h
        relation.where("#{relation.table_name}.json_attributes @> (?)::jsonb", attributes.to_json)
      end

    end
  end
end
