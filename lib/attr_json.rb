require "attr_json/version"

require "active_record"

require 'attr_json/config'
require 'attr_json/record'
require 'attr_json/model'
require 'attr_json/nested_attributes'
require 'attr_json/record/query_scopes'
require 'attr_json/type/polymorphic_model'

module AttrJson
  # We need to convert Symbols to strings a lot at present -- ActiveRecord does too, so
  # not too suprrising.
  #
  # In Rails 3.0 and above, we can use Symbol#name to get a frozen string back
  # and avoid extra allocations. https://bugs.ruby-lang.org/issues/16150
  #
  # Ruby 2.7 doens't yet have it though. As long as we are supporting ruby 2.7,
  # we'll just check at runtime to keep this lean
  if RUBY_VERSION.split('.').first.to_i >= 3
    def self.efficient_to_s(obj)
      if obj.kind_of?(Symbol)
        obj.name
      else
        obj.to_s
      end
    end
  else
    def self.efficient_to_s(obj)
      obj.to_s
    end
  end
end
