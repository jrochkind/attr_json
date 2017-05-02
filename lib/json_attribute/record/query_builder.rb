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
      def add_to_param_hash(param_hash, key_path_str, value)
        leaf_hash = param_hash
        key_path = key_path_str.to_s.split(".")

        attr_def = relation.json_attributes_registry.fetch(key_path.first)
        key = key_path.shift
        while(key_path.count > 0)
          # Yes, this is a weird and confusing API. To chain another
          # component on to our param_hash, we ask the current type
          # to do so, so it can do so in a type specific way. We give it
          # the current 'leaf_hash' the current attr_def (cause the type
          # doesn't know how it's been embedded), and the key it should apply.
          # It adds a NEW hash into the hash we gave it, and returns the
          # new hash -- our new 'leaf_hash' -- as well as returning the
          # the NEXT AttributeDefinition after applying the key we gave it.
          #
          # If you can figure out a less confusing way to design this, let me know. :)
          leaf_hash, attr_def =
            attr_def.type.add_keypath_component_to_query(
              leaf_hash,
              attr_def,
              key_path.first
            )
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
