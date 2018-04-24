module AttrJson
  module Model
    # Meant for mix-in in a AttrJson::Model class, defines some methods that
    # [cocoon](https://github.com/nathanvda/cocoon) insists upon, even though the
    # implementation doesn't really matter for getting cocoon to work with our Models
    # as nested models in forms with cocoon -- the methods just need to be there.
    module CocoonCompat
      extend ActiveSupport::Concern

      class_methods do
        # cocoon wants this. PR to cocoon to not?
        def reflect_on_association(*args)
          nil
        end
      end

      # cocoon insists on asking, we don't know the answer, we'll just say 'no'
      # PR to cocoon to not insist on this?
      def new_record?
        nil
      end
      def marked_for_destruction?
        nil
      end
    end
  end
end
