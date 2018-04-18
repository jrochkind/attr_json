module JsonAttribute
  module Model
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
