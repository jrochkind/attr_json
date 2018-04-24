require "json_attribute/version"

require "active_record"
require "active_record/connection_adapters/postgresql_adapter"

require 'json_attribute/record'
require 'json_attribute/model'
require 'json_attribute/nested_attributes'
require 'json_attribute/record/query_scopes'

# Dirty not supported on Rails 5.0
if Gem.loaded_specs["activerecord"].version.release >= Gem::Version.new('5.1')
  require 'json_attribute/record/dirty'
end

module JsonAttribute

end
