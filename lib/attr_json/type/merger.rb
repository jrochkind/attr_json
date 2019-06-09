module AttrJson
  module Type
    module Merger
      AR_VERSION = Gem.loaded_specs["activerecord"].version.release
      AR_5_2 = AR_VERSION >= Gem::Version.new('5.2') && AR_VERSION < Gem::Version.new('5.3')

      module Patch
        # This patch to #_update_row combines functionality from two methods
        # of AR:
        #
        #   - ActiveRecord::Base#_update_row
        #   - ActiveRecord::Base.update_record
        #
        # It replaces the value for the `ContainerAttribute` with a new value
        # that contains the changes to the json object and the removed keys.
        # Then, it builds a SQL literal that transforms them into an atomic
        # update operation using Postgres JSON functions.
        def _update_row(attribute_names, attempted_action = "update")
          klass = self.class
          pk = klass.primary_key
          values = attributes_with_values(attribute_names)
          constraints = { pk => id_in_database }

          # This is the only part of the code that differs from the original code.
          #
          # Patch
          merger = AttrJson::Type::Merger
          values1 = merger.replace(klass, values, changes)
          values2 = merger.substitude_values(klass, values1)
          # /Patch

          subs_constraints = klass.send(:_substitute_values, constraints)
          constraints = subs_constraints.map { |attr, bind|
            attr.eq(bind)
          }
          um = klass.arel_table.where(
            constraints.reduce(&:and)
          ).compile_update(values2, pk)

          klass.connection.update(um, "#{klass} Update")
        end
      end

      def self.enabled?(klass, name)
        klass.attribute_types[name].is_a?(ContainerAttribute)
      end

      # `literal` builds an Arel SqlLiteral attribute for the container column type.
      def self.literal(old_bind, value)
        changing, removed = value
        container_attribute = old_bind.value.type.container_attribute
        # Merge changing keys to the container column.
        sql = "(#{container_attribute} || '#{changing.to_json}'::jsonb)"
        # Remove the removed keys from the column.
        #
        # Example:
        #
        #   SELECT ('{"a": 1}'::jsonb || '{"b": 2}'::jsonb) - 'a' - 'b';
        #
        removed.each do |key|
          sql = sql + " - '#{key}'"
        end
        Arel::Nodes::SqlLiteral.new(sql)
      end

      # `substitude_values` builds query attribute and binds it to values.
      # It uses the SQL literal above if the patch is enabled for the
      # column type.
      def self.substitude_values(klass, values)
        values.map do |name, value|
          attr = klass.arel_attribute(name)
          old_bind = klass.predicate_builder.build_bind_attribute(name, value)
          bind = enabled?(klass, name) ? literal(old_bind, value) : old_bind
          [attr, bind]
        end
      end

      # `replace` replaces the value of the ContainerAttribute type with the
      # changes to the container column and the removed keys. These will be used
      # to build the SQL literal.
      def self.replace(klass, values, changes)
        values.map do |name, value|
          if enabled?(klass, name)
            c = changes[name]
            h = c.last
            unless h.nil? || h.kind_of?(Array)
              # Changing hash
              changing = h.reject { |k, v| c.first[k] == v }
              # Removed keys
              removed = c.first.keys - h.keys

              value = [changing, removed]
            end
          end
          [name, value]
        end.to_h
      end
    end
  end
end

# ActiveRecord integration.
ActiveSupport.on_load(:active_record) {
  patch = AttrJson::Type::Merger::Patch
  if AttrJson::Type::Merger::AR_5_2
    ActiveRecord::Base.send(:prepend, patch)
  end
}
