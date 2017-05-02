module JsonAttribute
  module Record
    class QueryBuilder
      attr_reader :relation, :input_attributes
      def initialize(relation, input_attributes)
        @relation = relation
        @input_attributes = input_attributes
      end

      def contains_relation
        result_relation = relation

        group_attributes_by_container.each do |container_attribute, attributes|
          attributes = attributes.collect do |key, value|
            attr_def = relation.json_attributes_registry[key.to_sym]

            [attr_def.store_key, attr_def.serialize(attr_def.cast value)]
          end.to_h
          result_relation = result_relation.where("#{relation.table_name}.#{container_attribute} @> (?)::jsonb", attributes.to_json)
        end

        result_relation
      end

      protected

      # returns a hash with keys container attributes, values hashes of attributes
      # belonging to that container attribute.
      def group_attributes_by_container
        @group_attributes_by_container ||= begin
          hash_by_container_attribute = {}

          input_attributes.each do |key, value|
            attr_def = relation.json_attributes_registry[key]
            container_attribute = attr_def.container_attribute

            hash_by_container_attribute[container_attribute] ||= {}
            hash_by_container_attribute[container_attribute][key] = value
          end

          hash_by_container_attribute
        end
      end
    end
  end
end
