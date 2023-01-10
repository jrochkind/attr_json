require 'attr_json/record/base'
require 'attr_json/nested_attributes'
require 'attr_json/record/query_scopes'

module AttrJson

  # The mix-in to provide AttrJson support to ActiveRecord::Base models.
  # We call it `Record` instead of `ActiveRecord` to avoid confusing namespace
  # shadowing errors, sorry!
  #
  # @example
  #       class SomeModel < ActiveRecord::Base
  #         include AttrJson::Record
  #
  #         attr_json :a_number, :integer
  #       end
  #
  # Most implementation is in AttrJson::Record::Base
  module Record
    extend ActiveSupport::Concern

    include AttrJson::Record::Base

    include AttrJson::NestedAttributes
    include AttrJson::Record::QueryScopes
  end
end
