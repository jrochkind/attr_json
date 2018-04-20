module JsonAttribute
  module NestedAttributes
    class Builder
      attr_reader :model, :attr_name, :attr_def

      def initialize(model, attr_name)
        @model, @attr_name = model, attr_name,
        @attr_def = model.class.json_attributes_registry[attr_name]
      end

      def build(params = {})
        if attr_def.array_type?
          model.send("#{attr_name}=", (model.send(attr_name) || []) + [params])
          return model.send("#{attr_name}").last
        else
          model.send("#{attr_name}=", params)
          return model.send("#{attr_name}")
        end
      end
    end
  end
end
