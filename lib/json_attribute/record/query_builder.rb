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
          param_hash = {}

          attributes.each do |key, value|
            add_to_param_hash(param_hash, key, value)
          end
          result_relation = result_relation.where("#{relation.table_name}.#{container_attribute} @> (?)::jsonb", param_hash.to_json)
        end

        result_relation
      end

      protected

      # Some tricky business taking care of key paths in a loopy unrolled
      # recursion kind of thing.
      def add_to_param_hash(param_hash, key, value)
        leaf_hash = param_hash
        key_path = key.to_s.split(".")

        attr_def = relation.json_attributes_registry.fetch(key_path.first)
        key = key_path.shift
        while(key_path.count > 0)
          leaf_hash = (param_hash[attr_def.store_key] ||= {})
          attr_def = attr_def.type.model.json_attributes_registry.fetch(key_path.first)
          key = key_path.shift
        end

        leaf_hash[attr_def.store_key] = attr_def.serialize(attr_def.cast value)

        return param_hash
      end

      # returns a hash with keys container attributes, values hashes of attributes
      # belonging to that container attribute.
      def group_attributes_by_container
        @group_attributes_by_container ||= begin
          hash_by_container_attribute = {}

          input_attributes.each do |key_path, value|
            key = key_path.to_s.split(".").first
            attr_def = relation.json_attributes_registry.fetch(key)
            container_attribute = attr_def.container_attribute

            hash_by_container_attribute[container_attribute] ||= {}
            hash_by_container_attribute[container_attribute][key_path] = value
          end

          hash_by_container_attribute
        end
      end
    end
  end
end
