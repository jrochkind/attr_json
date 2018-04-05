# JsonAttribute or Name Yet to Be Determined (suggest a name?)

Typed, structured, and compound/nested attributes via ActiveRecord
backed by [Postgres jsonb](https://www.postgresql.org/docs/9.5/static/datatype-json.html).
With dirty tracking support, and some query support.

Or, we could say: Use Postgres as a typed object store via ActiveRecord
('schemaless' on the postgres side, but with AR-style typing and casting
in your app), in the same models right next to ordinary ActiveRecord
column-backed attributes and associations.

Your `json_attribute`s act consistently with ordinary AR column-backed
attributes, with the implementation re-using as much of the existing AR architecture
as we can.

- - -
This is an in-progress experiment, not ready for production use, and may
include backwards-incompat API changes at any time before 1.0.
However, all features currently documented are fully implemented and appear to
be solid -- the README and other docs are real, not fantasy.

**Peer-review would be very appreciated**, especially but not only from those who
understand some of the depths of ActiveRecord. I very much appreciate hearing what you
think or what problems you find or additional features you desire, and also welcome
any comments on implementation and AR integration.
- - -

[![Build Status](https://travis-ci.org/jrochkind/json_attribute.svg?branch=master)](https://travis-ci.org/jrochkind/json_attribute)

## Tour of Features

```ruby
# migration
class CreatMyModels < ActiveRecord::Migration[5.0]
  def change
    create_table :my_models do |t|
      t.jsonb :json_attributes
      # an index would prob be wise here TBD
    end
  end
end

class MyModel < ActiveRecord::Base
   include JsonAttribute::Record

   # use any ActiveModel::Type types: string, integer, decimal (BigDecimal),
   # float, datetime, boolean.
   json_attribute :my_string, :string
   json_attribute :my_integer, :integer
   json_attribute :my_datetime, :datetime

   # You can have an _array_ of those things too.
   json_attribute :int_array, :integer, array: true

   #and/or defaults
   json_attribute :int_with_default, :integer, default: 100
end
```

You can treat these as if they were attributes; they have type-casting behavior
very much like ordinary ActiveRecord values -- even the arrays. Setting a value
will automatically cast it.

```ruby
model = MyModel.new
model.my_integer = "12"
model.my_integer # => 12
model.int_array = "12"
model.int_array # => [12]
model.my_datetime = "2016-01-01 17:45"
model.my_datetime # => a Time object representing that, just like AR would cast
```

These are all serialized to json in the `json_attributes` column, by default.
If you look at `model.json_attributes`, you'll see already cast values.
But one way to see something like what it's really like in the db is to
save and then use the standard Rails `*_before_type_cast` method.

```ruby
model.save!
model.json_attributes_before_type_cast
# => string containing: {"my_integer":12,"int_array":[12],"my_datetime":"2016-01-01T17:45:00.000Z"}
```

While the default is to assume you want to serialize in a column called
`json_attributes`, no worries, of course you can pick whatever named
jsonb column you like.

```ruby
class OtherModel < ActiveRecord::Base
  include JsonAttribute::Record

  # as a default for the model
  self.default_json_container_attribute = :some_other_column_name

  # now this is going to serialize to column 'some_other_column_name'
  json_attribute :my_int, :integer

  # Or on a per-attribute basis
  json_attribute :my_int, :integer, container_attribute: "yet_another_column_name"
end
```

You can also specify that the serialized JSON key
should be different than the attribute name with the `store_key` argument.

```ruby
class MyModel < ActiveRecord::Base
  include JsonAttribute::Record

  json_attribute :special_string, :string, store_key: "__my_string"
end

model = MyModel.new
model.special_string = "foo"
model.json_attributes # => {"__my_string"=>"foo"}
model.save!
model.json_attributes_before_type_cast # => string containing: {"__my_string":"foo"}
```

You can of course combine `array`, `default`, `store_key`, and `container_attribute`
params however you like, with whatever types you like: symbols resolvable
with `ActiveModel::Type.lookup`, or any [ActiveModel::Type::Value](https://apidock.com/rails/ActiveRecord/Attributes/ClassMethods/attribute) subclass, built-in or custom.

## Querying

There is some built-in support for querying using [postgres jsonb containment](https://www.postgresql.org/docs/9.5/static/functions-json.html)
(`@>`) operator. (or see [here](https://blog.hasura.io/the-unofficial-guide-to-jsonb-operators-in-postgres-part-1-7ad830485ddf) or [here](https://hackernoon.com/how-to-query-jsonb-beginner-sheet-cheat-4da3aa5082a3)). For now you need to additonally `include JsonAttribute::Record::QueryScopes`
to get this behavior.

```ruby
model = MyModel.create(my_string: "foo", my_integer: 100)

MyModel.jsonb_contains(my_string: "foo", my_integer: 100).to_sql
# SELECT "products".* FROM "products" WHERE (products.json_attributes @> ('{"my_string":"foo","my_integer":100}')::jsonb)
MyModel.jsonb_contains(my_string: "foo", my_integer: 100).first
# Implemented with scopes, this is an ordinary relation, you can
# combine it with whatever, just like ordinary `where`.

# typecasts much like ActiveRecord on query too:
MyModel.jsonb_contains(my_string: "foo", my_integer: "100")
# no problem

# works for arrays too
model = MyModel.create(int_array: [10, 20, 30])
MyModel.jsonb_contains(int_array: 10) # finds it
MyModel.jsonb_contains(int_array: [10]) # still finds it
MyModel.jsonb_contains(int_array: [10, 20]) # it contains both, so still finds it
MyModel.jsonb_contains(int_array: [10, 1000]) # nope, returns nil, has to contain ALL listed in query for array args
```

`jsonb_contains` of course handles any `store_key` you have set (you should specify
attribute name, it'll actually query on store_key), as well as any
`container_attribute` (it'll look in the proper jsonb column).

Anything you can do with `jsonb_contains` should be handled
by a [postgres `USING GIN` index](https://www.postgresql.org/docs/9.5/static/datatype-json.html#JSON-INDEXING)
(I think! can anyone help confirm/deny?). To be sure, I recommend you
investigate: Check out `to_sql` on any query to see what jsonb SQL it generates,
and explore if you have the indexes you need.

## Nested/Structured/Compound data

`JsonAttribute::Model` lets you make ActiveModel objects that always
represent something that can be serialized to a json hash, and they can
be used as types for your top-level JsonAttribute::Record.

That is, you can serialize complex object-oriented graphs of models into a single
jsonb column, and get them back as they went in.

`JsonAttribute::Model` has an identical `json_attribute` api to
`JsonAttribute::Record`, with the exception that `container_attribute` is not supported.

```ruby
class LangAndValue
  include JsonAttribute::Model

  json_attribute :lang, :string, default: "en"
  json_attribute :value, :string

  # Validations work fine, and will post up to parent record
  validates :lang, inclusion_in: I18n.config.available_locales.collect(&:to_s)
end

class MyModel < ActiveRecord::Base
  include JsonAttribute::Record
  include JsonAttribute::Record::QueryScopes

  json_attribute :lang_and_value, LangAndValue.to_type

  # YES, you can even have an array of them
  json_attribute :lang_and_value_array, LangAndValue.to_type, array: true
end

# Set with a model object, in initializer or writer
m = MyModel.new(lang_and_value: LangAndValue.new(lang: "fr", value: "S'il vous plaît"))
m.lang_and_value = LangAndValue.new(lang: "es", value: "hola")
m.lang_and_value
# => #<LangAndValue:0x007fb64f12bb70 @attributes={"lang"=>"es", "value"=>"hola"}>
m.save!
m.json_attributes_before_type_cast
# => string containing: {"lang_and_value":{"lang":"es","value":"hola"}}

# Or with a hash, no problem.

m = MyModel.new(lang_and_value: { lang: 'fr', value: "S'il vous plaît"})
m.lang_and_value = { lang: 'en', value: "Hey there" }
m.save!
m.json_attributes_before_type_cast
# => string containing: {"lang_and_value":{"lang":"en","value":"Hey there"}}
found = MyModel.find(m.id)
m.lang_and_value
# => #<LangAndValue:0x007fb64eb78e58 @attributes={"lang"=>"en", "value"=>"Hey there"}>

# Arrays too, yup

m = MyModel.new(lang_and_value_array: [{ lang: 'fr', value: "S'il vous plaît"}, { lang: 'en', value: "Hey there" }])
m.lang_and_value_array
# => [#<LangAndValue:0x007f89b4f08f30 @attributes={"lang"=>"fr", "value"=>"S'il vous plaît"}>, #<LangAndValue:0x007f89b4f086e8 @attributes={"lang"=>"en", "value"=>"Hey there"}>]
m.save!
m.json_attributes_before_type_cast
# => string containing: {"lang_and_value_array":[{"lang":"fr","value":"S'il vous plaît"},{"lang":"en","value":"Hey there"}]}
```

You can nest JsonAttribute::Model objects inside each other, as deeply as you like --
although very large/complex graphs _may_ have performance implications, test/investigate.

```ruby
class SomeLabels
  include JsonAttribute::Model

  json_attribute :hello, LangAndValue.to_type, array: true
  json_attribute :goodbye, LangAndValue.to_type, array: true
end
class MyModel < ActiveRecord::Base
  include JsonAttribute::Record
  include JsonAttribute::Record::QueryScopes

  json_attribute :my_labels, SomeLabels.to_type
end

m = MyModel.new
m.my_labels = {}
m.my_labels
# => #<SomeLabels:0x007fed2a3b1a18>
m.my_labels.hello = [{lang: 'en', value: 'hello'}, {lang: 'es', value: 'hola'}]
m.my_labels
# => #<SomeLabels:0x007fed2a3b1a18 @attributes={"hello"=>[#<LangAndValue:0x007fed2a0eafc8 @attributes={"lang"=>"en", "value"=>"hello"}>, #<LangAndValue:0x007fed2a0bb4d0 @attributes={"lang"=>"es", "value"=>"hola"}>]}>
m.my_labels.hello.find { |l| l.lang == "en" }.value = "Howdy"
m.save!
m.json_attributes
# => {"my_labels"=>#<SomeLabels:0x007fed2a714e80 @attributes={"hello"=>[#<LangAndValue:0x007fed2a714cf0 @attributes={"lang"=>"en", "value"=>"Howdy"}>, #<LangAndValue:0x007fed2a714ac0 @attributes={"lang"=>"es", "value"=>"hola"}>]}>}
m.json_attributes_before_type_cast
# => string containing: {"my_labels":{"hello":[{"lang":"en","value":"Howdy"},{"lang":"es","value":"hola"}]}}
```

**GUESS WHAT?** You can **QUERY** nested structures with `jsonb_contains`,
using a dot-keypath notation, even through arrays as in this case. Your specific
defined `json_attribute` types determine the query and type-casting.

```ruby
MyModel.jsonb_contains("my_labels.hello.lang" => "en").to_sql
# => SELECT "products".* FROM "products" WHERE (products.json_attributes @> ('{"my_labels":{"hello":[{"lang":"en"}]}}')::jsonb)
MyModel.jsonb_contains("my_labels.hello.lang" => "en").first


# also can give hashes, at any level, or models themselves. They will
# be cast. Trying to make everything super consistent with no surprises.

MyModel.jsonb_contains("my_labels.hello" => LangAndValue.new(lang: 'en')).to_sql
# => SELECT "products".* FROM "products" WHERE (products.json_attributes @> ('{"my_labels":{"hello":[{"lang":"en"}]}}')::jsonb)

MyModel.jsonb_contains("my_labels.hello" => {"lang" => "en"}).to_sql
# => SELECT "products".* FROM "products" WHERE (products.json_attributes @> ('{"my_labels":{"hello":[{"lang":"en"}]}}')::jsonb)

```

Remember, we're using a postgres containment (`@>`) operator, so queries
always mean 'contains' -- the previous query needs a `my_labels.hello`
which is a hash that includes the key/value, `lang: en`, it can have
other key/values in it too.

(No built-in way currently to do `like` queries?)

## Dirty tracking

Full change-tracking, ActiveRecord::Attributes::Dirty-style, is available in
Rails 5.1+ on `json_attribute`s on your ActiveRecord classes that include
`JsonAttribute::Record`, by including `JsonAttribute::Record::Dirty`.
Change-tracking methods are available off the `json_attribute_changes` method.

    class MyModel < ActiveRecord::Base
       include JsonAttribute::Record
       include JsonAttribute::Record::Dirty

       json_attribute :str, :string
    end

    model = MyModel.new
    model.str = "old"
    model.save
    model.str = "new"

    # All and only "new" style dirty tracking methods (Raisl 5.1+)
    # are available:

    model.json_attribute_changes.saved_changes
    model.json_attribute_changes.changes_to_save
    model.json_attribute_changes.saved_change_to_str?
    model.json_attribute_changes.saved_change_to_str
    model.json_attribute_changes.will_save_change_to_str?
    # etc

More options are available, including merging changes from 'ordinary'
ActiveRecord attributes in. See docs on [Dirty Tracking](./doc_src/dirty_tracking.md)

## Do you want this?

Why might you want this?

* You have complicated data, which you want to access in object-oriented
  fashion, but want to avoid very complicated normalized rdbms schema --
  and are willing to trade the powerful complex querying support normalized rdbms
  schema gives you.

* Single-Table Inheritance, with sub-classes that have non-shared
  data fields. You rather not make all those columns, some of which will then also appear
  to inapplicable sub-classes.

* A "content management system" type project, where you need complex
  structured data of various types, maybe needs to be vary depending
  on plugins or configuration, or for different article types -- but
  doesn't need to be very queryable generally.

* You want to version your models, which is tricky with associations between models.
  Minimize associations by inlining the complex data into one table row.

* Generally, we're turning postgres into a _simple_ object-oriented
  document store. That can be mixed with an rdbms. The very same
  row in a table in your db can have document-oriented json data _and_ foreign keys
  and real rdbms associations to other rows. And it all just
  feels like ActiveRecord, mostly.

Why might you _not_ want this?

* An rdbms and SQL is a wonderful thing, if you need sophisticated
  querying and reporting with reasonable performance, complex data
  in a single jsonb probably isn't gonna be the best.

* This is pretty well-designed code that _mostly_ only uses
  fairly stable and public Rails API, but there is still some
  risk of tying your boat to it, it's not Rails itself, and there is
  some risk it won't keep up with Rails in the future.


## Note on Optimistic Locking

When you save a record with any changes to any json_attributes, it will
overwrite the _whole json structure_ in the relevant column for that row.
Unlike ordinary AR attributes where updates just touch changed attributes.

Becuase of this, you probably want to seriously consider using ActiveRecord
[Optimistic Locking](http://api.rubyonrails.org/classes/ActiveRecord/Locking/Optimistic.html)
to prevent overwriting other updates from processes.

## State of Code, and To Be Done

Work in progress. But working pretty well. There are some known edge cases,
or questions about the proper semantics, or proper way to interact with
existing ActiveRecord API -- search code for "TODO".

While the _querying_ stuff relies on postgres-jsonb-specific features,
the stuff to simply store complex nested typed data in a json column
doesn't really have any postgres-specifics, and the design should work
on a MySQL json column, or possibly any ActiveRecord column `serialize`d
to a json-like hash even in a blob/text column. It would require just a
couple tweaks and perhaps another layer of abstraction; my brain was
too full and the code complex/abstract enough for now, but could come later.

This is sort of a proof of concept at present, there are many features
that still need attending to, to really smooth off the edges.


* Polymorphic JSON attributes.

* partial updates for json hashes, use postgres jsonb merge operators to only overwrite what changed

* I think it's important to be able to use these, even nested/array, with
  _Rails forms_, in a natural way. (also with simple_form) This ought to be fairly straightforward,
  the parameter format here is actually a lot _simpler_ than
  what Rails needs to do for normalized rdbms data, but it might
  run into Rails' assumptions about that extra complexity,
  need to experiment with it.

* seamless compatibility with ransack

* Should we give JsonAttribute::Model a before_serialize hook that you might
  want to use similar to AR before_save?  Should JsonAttribute::Models
  raise on trying to serialize an invalid model?

* There are limits to what you can do with just jsonb_contains
  queries. We could support operations like `>`, `<`, `<>`
  as [jsonb_accessor](https://github.com/devmynd/jsonb_accessor),
  even accross keypaths -- but the semantics get confusing
  accross keypaths, especially with multiple keypaths
  expressed. The proper postgres indexing also
  gets confusing accross keypaths. Even with jsonb
  contains, the semantics get confusing, it's not always
  clear what you're asking for. Full query language support
  for something similar to what mongodb does is probably quite
  possible to translate to postgres jsonb, but a bunch of work to write,
  and confusing how indexes apply. (You can always use a
  before_safe to denormalize/renormalize copy your data into
  ordinary AR columns/associations though.)

* We could/should probably support `jsonb_order` clauses, even
  accross key paths, like jsonb_accessor.

* Could we make these attributes work in ordinary AR where, same
  as they do in jsonb_contains? Maybe.

## Acknowledements and Prior Art

* The excellent work [Sean Griffin](https://twitter.com/sgrif) did on ActiveModel::Type
  really lays the groundwork and makes this possible. Plus many other Rails developers.
  Rails has a reputation for being composed of messy or poorly designed code, but
  it's some really nice design in Rails that allows us to do some pretty powerful
  stuff here, in surprisingly few lines of code.

* The existing [jsonb_accessor](https://github.com/devmynd/jsonb_accessor) was
  an inspiration, and provided some good examples of how to do some things
  with AR and ActiveModel::Types. I [started out trying to figure out](https://github.com/devmynd/jsonb_accessor/issues/69#issuecomment-294081059)
  how to fit in nested hashes to jsonb_accessor... but ended up pretty much rewriting it entirely,
  to lean on object-oriented polymorphism and ActiveModel::Type a lot heavier and have
  the API and internals I wanted/imagined.

* Took a look at existing [active_model_attributes](https://github.com/Azdaroth/active_model_attributes) too.

* Didn't actually notice existing [json_attributes](https://github.com/joel/json_attributes)
  until I was well on my way here. I think it's not updated for Rails5 or type-aware,
  haven't looked at it too much.

(Btw, so many names are taken... what should I call this gem?)
