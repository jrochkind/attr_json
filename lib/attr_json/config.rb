module AttrJson
  # Intentionally non-mutable, to avoid problems with subclass inheritance
  # and rails class_attribute. Instead, you set to new Config object
  # changed with {#merge}.
  class Config
    RECORD_ALLOWED_KEYS = %i{default_container_attribute}
    MODEL_ALLOWED_KEYS = %i{unknown_key}
    DEFAULTS = {
      default_container_attribute: "json_attributes",
      unknown_key: :raise
    }

    (MODEL_ALLOWED_KEYS + RECORD_ALLOWED_KEYS).each do |key|
      define_method(key) do
        attributes[key]
      end
    end

    attr_reader :mode

    def initialize(options = {})
      @mode = options.delete(:mode)
      unless mode == :record || mode == :model
        raise ArgumentError, "required :mode argument must be :record or :model"
      end
      valid_keys = mode == :record ? RECORD_ALLOWED_KEYS : MODEL_ALLOWED_KEYS
      options.assert_valid_keys(valid_keys)

      options.reverse_merge!(DEFAULTS.slice(*valid_keys))

      @attributes = options
    end

    # Returns a new Config object, with changes merged in.
    def merge(changes = {})
      self.class.new(attributes.merge(changes).merge(mode: mode))
    end

    protected

    def attributes
      @attributes
    end
  end
end
