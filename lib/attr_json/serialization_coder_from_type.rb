module AttrJson

  # A little wrapper to provide an object that provides #dump and #load method for use
  # as a coder second-argument for [ActiveRecord Serialization](https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Serialization/ClassMethods.html),
  # that simply delegates to #serialize and #deserialize from a ActiveModel::Type object.
  #
  # Created to be used with an AttrJson::Model type (AttrJson::Type::Model), but hypothetically
  # could be a shim from anything with serialize/deserialize to dump/load instead.
  #
  #    class ValueModel
  #      include AttrJson::Model
  #      attr_json :some_string, :string
  #    end
  #
  #    class SomeModel < ApplicationRecord
  #      serialize :some_json_column, ValueModel.to_serialize_coder
  #    end
  #
  # Note when used with an AttrJson::Model, it will dump/load from a HASH, not a
  # string. It assumes it's writing to a Json(b) column that wants/provides hashes,
  # not strings.
  class SerializationCoderFromType
    attr_reader :type
    def initialize(type)
      @type = type
    end

    # Dump and load methods to support ActiveRecord Serialization
    # too.
    def dump(value)
      type.serialize(value)
    end

    # Dump and load methods to support ActiveRecord Serialization
    # too. https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Serialization/ClassMethods.html
    def load(value)
      type.deserialize(value)
    end
  end
end
