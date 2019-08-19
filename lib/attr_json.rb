require "attr_json/version"

require "active_record"

require 'attr_json/config'
require 'attr_json/record'
require 'attr_json/model'
require 'attr_json/nested_attributes'
require 'attr_json/record/query_scopes'
require 'attr_json/type/polymorphic_model'

# Dirty not supported on Rails 5.0
if Gem.loaded_specs["activerecord"].version.release >= Gem::Version.new('5.1')
  require 'attr_json/record/dirty'
end

module AttrJson

end
