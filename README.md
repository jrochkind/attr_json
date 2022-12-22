# AttrJson
[![CI Status](https://github.com/jrochkind/attr_json/workflows/CI/badge.svg?branch=master)](https://github.com/jrochkind/attr_json/actions?query=workflow%3ACI+branch%3Amaster)
[![CI Status](https://github.com/jrochkind/attr_json/workflows/CI%20on%20Future%20Rails%20Versions/badge.svg?branch=master)](https://github.com/jrochkind/attr_json/actions?query=workflow%3A%22CI+on+Future+Rails+Versions%22+branch%3Amaster)
[![Gem Version](https://badge.fury.io/rb/attr_json.svg)](https://badge.fury.io/rb/attr_json)


ActiveRecord attributes stored serialized in a json column, super smooth. For Rails 6.0.x through 7.0.x. Ruby 2.6+.

Typed and cast like Active Record. Supporting [nested models](#nested), [dirty tracking](#ar_attributes), some [querying](#querying) (with postgres [jsonb](https://www.postgresql.org/docs/9.5/static/datatype-json.html) contains), and [working smoothy with form builders](#forms).

*Use your database as a typed object store via ActiveRecord, in the same models right next to ordinary ActiveRecord column-backed attributes and associations. Your json-serialized `attr_json` attributes use as much of the existing ActiveRecord architecture as we can.*

[Why might you want or not want this?](#why)

Developed for postgres, but most features should work with MySQL json columns too, although
has not yet been tested with MySQL.

## Basic Use

```ruby
# migration
class CreatMyModels < ActiveRecord::Migration[5.0]
  def change
    create_table :my_models do |t|
      t.jsonb :json_attributes
    end

    # If you plan to do any querying with jsonb_contains below..
    add_index :my_models, :json_attributes, using: :gin
  end
end

class MyModel < ActiveRecord::Base
   include AttrJson::Record

   # use any ActiveModel::Type types: string, integer, decimal (BigDecimal),
   # float, datetime, boolean.
   attr_json :my_string, :string
   attr_json :my_integer, :integer
   attr_json :my_datetime, :datetime

   # You can have an _array_ of those things too. It will ordinarily default to empty array.
   attr_json :int_array, :integer, array: true

   #and/or defaults
   attr_json :int_with_default, :integer, default: 100
end
```

These attributes have type-casting behavior very much like ordinary ActiveRecord values.

```ruby
model = MyModel.new
model.my_integer = "12"
model.my_integer # => 12
model.int_array = "12"
model.int_array # => [12]
model.my_datetime = "2016-01-01 17:45"
model.my_datetime # => a Time object representing that, just like AR would cast
```

You can use ordinary ActiveRecord validation methods with `attr_json` attributes.

All the `attr_json` attributes are serialized to json as keys in a hash, in a database jsonb/json column. By default, in a column `json_attributes`.
If you look at `model.json_attributes`, you'll see values already cast to their ruby representations.

To see JSON representations, we can use Rails [\*\_before_type_cast](https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/BeforeTypeCast.html) methods,  [\*\-in_database](https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Dirty.html#method-i-attribute_in_database) and [\*\_for_database] methods (Rails 7.0+ only).

These methods can all be called on ont the container `json_attributes` json hash attribute (generally showing serialized JSONto string), or any individual attribute (generally showing in-memory JSON-able object). [This is a bit confusing and possibly not entirely consistent, needs more investigation.]

## Specifying db column to use

While the default is to assume you want to serialize in a column called
`json_attributes`, no worries, of course you can pick whatever named
jsonb column you like, class-wide or per-attribute.

```ruby
class OtherModel < ActiveRecord::Base
  include AttrJson::Record

  # as a default for the model
  attr_json_config(default_container_attribute: :some_other_column_name)

  # now this is going to serialize to column 'some_other_column_name'
  attr_json :my_int, :integer

  # Or on a per-attribute basis
  attr_json :my_int, :integer, container_attribute: "yet_another_column_name"
end
```

## Store key different than attribute name/methods

You can also specify that the serialized JSON key
should be different than the attribute name/methods, by using the `store_key` argument.

```ruby
class MyModel < ActiveRecord::Base
  include AttrJson::Record

  attr_json :special_string, :string, store_key: "__my_string"
end

model = MyModel.new
model.special_string = "foo"
model.json_attributes # => {"__my_string"=>"foo"}
model.save!
model.json_attributes_before_type_cast # => string containing: {"__my_string":"foo"}
```

You can of course combine `array`, `default`, `store_key`, and `container_attribute`
params however you like, with whatever types you like: symbols resolvable
with `ActiveRecord::Type.lookup`, or any [ActiveModel::Type::Value](https://apidock.com/rails/ActiveRecord/Attributes/ClassMethods/attribute) subclass, built-in or custom.

You can register your custom `ActiveModel::Type::Value` in a Rails initializer or early on in your app boot sequence:

```ruby
ActiveRecord::Type.register(:my_type, MyActiveModelTypeSubclass)
```

<a name="querying"></a>
## Querying

There is some built-in support for querying using [postgres jsonb containment](https://www.postgresql.org/docs/9.5/static/functions-json.html)
(`@>`) operator. (or see [here](https://blog.hasura.io/the-unofficial-guide-to-jsonb-operators-in-postgres-part-1-7ad830485ddf) or [here](https://hackernoon.com/how-to-query-jsonb-beginner-sheet-cheat-4da3aa5082a3)). For now you need to additionally `include AttrJson::Record::QueryScopes`
to get this behavior.

```ruby
model = MyModel.create(my_string: "foo", my_integer: 100)

MyModel.jsonb_contains(my_string: "foo", my_integer: 100).to_sql
# SELECT "products".* FROM "products" WHERE (products.json_attributes @> ('{"my_string":"foo","my_integer":100}')::jsonb)
MyModel.jsonb_contains(my_string: "foo", my_integer: 100).first
# Implemented with scopes, this is an ordinary relation, you can
# combine it with whatever, just like ordinary `where`.

MyModel.not_jsonb_contains(my:string: "foo", my_integer: 100).to_sql
# SELECT "products".* FROM "products" WHERE NOT (products.json_attributes @> ('{"my_string":"foo","my_integer":100}')::jsonb)

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

`jsonb_contains` will handle any `store_key` you have set -- you should specify
attribute name, it'll actually query on store_key. And properly handles any
`container_attribute` -- it'll look in the proper jsonb column.

Anything you can do with `jsonb_contains` should be handled
by a [postgres `USING GIN` index](https://www.postgresql.org/docs/9.5/static/datatype-json.html#JSON-INDEXING)
(I think! can anyone help confirm/deny?). To be sure, I recommend you
investigate: Check out `to_sql` on any query to see what jsonb SQL it generates,
and explore if you have the indexes you need.

<a name="nested"></a>
## Nested models -- Structured/compound data

The `AttrJson::Model` mix-in lets you make ActiveModel::Model objects that can be round-trip serialized to a json hash, and they can be used as types for your top-level AttrJson::Record.
`AttrJson::Model`s can contain other AJ::Models, singly or as arrays, nested as many levels as you like.

That is, you can serialize complex object-oriented graphs of models into a single
jsonb column, and get them back as they went in.

`AttrJson::Model` has an identical `attr_json` api to
`AttrJson::Record`, with the exception that `container_attribute` is not supported.

```ruby
class LangAndValue
  include AttrJson::Model

  attr_json :lang, :string, default: "en"
  attr_json :value, :string

  # Validations work fine, and will post up to parent record
  validates :lang, inclusion_in: I18n.config.available_locales.collect(&:to_s)
end

class MyModel < ActiveRecord::Base
  include AttrJson::Record
  include AttrJson::Record::QueryScopes

  attr_json :lang_and_value, LangAndValue.to_type

  # YES, you can even have an array of them
  attr_json :lang_and_value_array, LangAndValue.to_type, array: true
end

# Set with a model object, in initializer or writer
m = MyModel.new(lang_and_value: LangAndValue.new(lang: "fr", value: "S'il vous plaît"))
m.lang_and_value = LangAndValue.new(lang: "es", value: "hola")
m.lang_and_value
# => #<LangAndValue:0x007fb64f12bb70 @attributes={"lang"=>"es", "value"=>"hola"}>
m.save!
m.attr_jsons_before_type_cast
# => string containing: {"lang_and_value":{"lang":"es","value":"hola"}}

# Or with a hash, no problem.

m = MyModel.new(lang_and_value: { lang: 'fr', value: "S'il vous plaît"})
m.lang_and_value = { lang: 'en', value: "Hey there" }
m.save!
m.attr_jsons_before_type_cast
# => string containing: {"lang_and_value":{"lang":"en","value":"Hey there"}}
found = MyModel.find(m.id)
m.lang_and_value
# => #<LangAndValue:0x007fb64eb78e58 @attributes={"lang"=>"en", "value"=>"Hey there"}>

# Arrays too, yup

m = MyModel.new(lang_and_value_array: [{ lang: 'fr', value: "S'il vous plaît"}, { lang: 'en', value: "Hey there" }])
m.lang_and_value_array
# => [#<LangAndValue:0x007f89b4f08f30 @attributes={"lang"=>"fr", "value"=>"S'il vous plaît"}>, #<LangAndValue:0x007f89b4f086e8 @attributes={"lang"=>"en", "value"=>"Hey there"}>]
m.save!
m.attr_jsons_before_type_cast
# => string containing: {"lang_and_value_array":[{"lang":"fr","value":"S'il vous plaît"},{"lang":"en","value":"Hey there"}]}
```

You can nest AttrJson::Model objects inside each other, as deeply as you like.

### Model-type defaults

If you want to set a default for an AttrJson::Model type, you should use a proc argument for
the default, to avoid accidentally re-using a shared global default value, similar to issues
people have with ruby Hash default.

```ruby
  attr_json :lang_and_value, LangAndValue.to_type, default: -> { LangAndValue.new(lang: "en", value: "default") }
```

You can also use a Hash value that will be cast to your model, no need for proc argument
in this case.

```ruby
  attr_json :lang_and_value, LangAndValue.to_type, default: { lang: "en", value: "default" }
```


### Polymorphic model types

There is some support for "polymorphic" attributes that can hetereogenously contain instances of different AttrJson::Model classes, see comment docs at [AttrJson::Type::PolymorphicModel](./lib/attr_json/type/polymorphic_model.rb).


```ruby
class SomeLabels
  include AttrJson::Model

  attr_json :hello, LangAndValue.to_type, array: true
  attr_json :goodbye, LangAndValue.to_type, array: true
end
class MyModel < ActiveRecord::Base
  include AttrJson::Record
  include AttrJson::Record::QueryScopes

  attr_json :my_labels, SomeLabels.to_type
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
m.attr_jsons
# => {"my_labels"=>#<SomeLabels:0x007fed2a714e80 @attributes={"hello"=>[#<LangAndValue:0x007fed2a714cf0 @attributes={"lang"=>"en", "value"=>"Howdy"}>, #<LangAndValue:0x007fed2a714ac0 @attributes={"lang"=>"es", "value"=>"hola"}>]}>}
m.attr_jsons_before_type_cast
# => string containing: {"my_labels":{"hello":[{"lang":"en","value":"Howdy"},{"lang":"es","value":"hola"}]}}
```

**GUESS WHAT?** You can **QUERY** nested structures with `jsonb_contains`,
using a dot-keypath notation, even through arrays as in this case. Your specific
defined `attr_json` types determine the query and type-casting.

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
other key/values in it too.  String values will need to match exactly.

## Single AttrJson::Model serialized to an entire json column

The main use case of the gem is set up to let you combine multiple primitives and nested models
under different keys combined in a single json or jsonb column.

But you may also want to have one AttrJson::Model class that serializes to map one model class, as
a hash, to an entire json column on it's own.

`AttrJson::Model` can supply a simple coder for the [ActiveRecord serialization](https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Serialization/ClassMethods.html)
feature  to easily do that.

```ruby
class MyModel
  include AttrJson::Model

  attr_json :some_string, :string
  attr_json :some_int, :int
end

class MyTable < ApplicationRecord
  serialize :some_json_column, MyModel.to_serialization_coder
end

MyTable.create(some_json_column: MyModel.new(some_string: "string"))

# will cast from hash for you
MyTable.create(some_json_column: { some_int: 12 })

# etc
```

To avoid errors raised at inconvenient times, we recommend you set these settings to make 'bad'
data turn into `nil`, consistent with most ActiveRecord types:

```ruby
class MyModel
  include AttrJson::Model

  attr_json_config(bad_cast: :as_nil, unknown_key: :strip)
  # ...
end
```

And/or define a setter method to cast, and raise early on data problems:

```ruby
class MyTable < ApplicationRecord
  serialize :some_json_column, MyModel.to_serialization_coder

  def some_json_column=(val)
    super(   )
  end
end
```

Serializing a model to an entire json column is a relatively recent feature, please let us know how it's working for you.

<a name="arbitrary-json-data"></a>
## Storing Arbitrary JSON data

Arbitrary JSON data (hashes, arrays, primitives of any depth) can be stored within attributes by using the rails built in `ActiveModel::Type::Value` as the attribute type. This is basically a "no-op" value type -- JSON alone will be used to serialize/deserialize whatever values you put there, because of the json type on the container field.

```ruby
class MyModel < ActiveRecord::Base
  include AttrJson::Record

  attr_json :arbitrary_hash, ActiveModel::Type::Value.new
end

```


<a name="forms"></a>
## Forms and Form Builders

Use with Rails form builders is supported pretty painlessly. Including with [simple_form](https://github.com/plataformatec/simple_form) and [cocoon](https://github.com/nathanvda/cocoon) (integration-tested in CI).

If you have nested AttrJson::Models you'd like to use in your forms much like Rails associated records: Where you would use Rails `accepts_nested_attributes_for`, instead `include AttrJson::NestedAttributes` and use `attr_json_accepts_nested_attributes_for`. Multiple levels of nesting are supported.

For more info, see doc page on [Use with Forms and Form Builders](doc_src/forms.md).

<a name="ar_attributes"></a>
## ActiveRecord Attributes and Dirty tracking

We endeavor to make record-level `attr_json` attributes available as standard ActiveRecord attributes, supporting that full API.

Standard [Rails dirty tracking](https://api.rubyonrails.org/classes/ActiveModel/Dirty.html) should work properly with AttrJson::Record attributes! We have a test suite demonstrating.

We actually keep the "canonical" copy of data inside the "container attribute" hash in the ActiveRecord model. This is because this is what will actually get saved when you save. So we have two copies, that we do our best to keep in sync.

They get out of sync if you are doing unusual things like using the ActiveRecord attribute API directly (like calling `write_attribute` with an attr_json attribute). Even if this happens, mostly you won't notice. But one thing it will effect is dirty tracking.

If you ever need to sync the ActiveRecord attribute values from the AttrJson "canonical" copies, you can call `active_record_model.attr_json_sync_to_rails_attributes`. If you wanted to be 100% sure of dirty tracking, I suppose you could always call this method first. Sorry, this is the best we could do!

Note that ActiveRecord DirtyTracking will give you ruby objects, for instance for nested models, you might get:

```ruby
record_obj.attribute_change_to_be_saved(:nested_model)
# => [#<object>, #<object>]
```

If you want to see JSON instead, you could call #as_json on the values. The Rails [\*\_before_type_cast](https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/BeforeTypeCast.html) and [\*\-in_database](https://api.rubyonrails.org/classes/ActiveRecord/AttributeMethods/Dirty.html#method-i-attribute_in_database) methods may also be useful.

<a name="why"></a>
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
  doesn't need to be very queryable generally -- or you have means of querying
  other than a normalized rdbms schema.

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

When you save a record with any changes to any attr_jsons, it will
overwrite the _whole json structure_ in the relevant column for that row.
Unlike ordinary AR attributes where updates just touch changed attributes.

Becuase of this, you probably want to seriously consider using ActiveRecord
[Optimistic Locking](http://api.rubyonrails.org/classes/ActiveRecord/Locking/Optimistic.html)
to prevent overwriting other updates from processes.

## State of Code, and To Be Done

This code is solid and stable and is being used in production by at least a handful of people, including the primary maintainer, jrochkind.

The project is currently getting very little maintainance -- and is still working reliably through Rails releases. It is tested on edge rails and ruby (and has needed very few if any changes with subsequent releases), and I endeavor to keep it working as Rails keeps releasing.

In order to keep the low-maintenace scenario sustainable, I am *very* cautious accepting new features, especially if they increase code complexity at all. Even if you have a working PR, I may be reluctant to accept it. I'm prioritizing sustainability and stability over new features, and so far this is working out well. However, discussion is always welcome! Especially when paired with code (failing tests for the bugfix or feature you want are super helpful on their own!).

We are committed to [semantic versioning](https://semver.org/) and will endeavor to release no backwards breaking changes without a major version. We are also serious about minimizing backwards incompat releases altogether (ie minimiing major version releases).

Feedback of any kind of _very welcome_, please feel free to use the issue tracker. It is hard to get a sense of how many people are actually using this, which is helpful both for my own sense of reward and for anyone to get a sense of the size of the userbase -- feel free to say hi and let us know how you are using it!

Except for the jsonb_contains stuff using postgres jsonb contains operator, I don't believe any postgres-specific features are used. It ought to work with MySQL, testing and feedback welcome. (Or a PR to test on MySQL?).  My own interest is postgres.

This is still mostly a single-maintainer operation, so has all the sustainability risks of that. Although there are other people using and contributing to it, check out the Github Issues and Pull Request tabs yourself to get a sense.

### Possible future features:

* Make AttrJson::Model lean more heavily on ActiveModel::Attributes API that did not fully exist in first version of attr_json [hope for a future attr_json 2.0 release]

* Make AttrJson::Record insist on creating rails cover attributes (no longer optional)  and integrating more fully into rails, including rails dirty tricking, eliminating need for custom dirty tracking implementation. Overall decrease in lines of code. Can use jsonb_accessor as guide for some aspects. [hope for inclusion in future attr_json 2.0 release]

* partial updates for json hashes would be really nice: Using postgres jsonb merge operators to only overwrite what changed. In my initial attempts, AR doesn't make it easy to customize this. [update: this is hard, probably not coming soon]

* seamless compatibility with ransack [update: not necessarily prioritized]

* Should we give AttrJson::Model a before_serialize hook that you might
  want to use similar to AR before_save?  Should AttrJson::Models
  raise on trying to serialize an invalid model? [update: eh, hasn't really come up]

* There are limits to what you can do with just jsonb_contains
  queries. We could support operations like `>`, `<`, `<>`
  as [jsonb_accessor](https://github.com/devmynd/jsonb_accessor),
  even accross keypaths. (At present, you could use a
  before_savee to denormalize/renormalize copy your data into
  ordinary AR columns/associations for searching. Or perhaps a postgres ts_vector for text searching. Needs to be worked out.) [update: interested, but not necessarily prioritized. This one would be interesting for a third-party PR draft!]

* We could/should probably support `jsonb_order` clauses, even
  accross key paths, like jsonb_accessor. [update: interested but not necessarily prioritized]

* Could we make these attributes work in ordinary AR where, same
  as they do in jsonb_contains? Maybe. [update: probably not]

## Development

While `attr_json` depends only on `active_record`, we run integration tests in the context of a full Rails app, in order to test working with simple_form and cocoon, among other things.  (Via [combustion](https://github.com/pat/combustion), with app skeleton at [./spec/internal](./spec/internal)).

At present this does mean that all our automated tests are run in a full Rails environment, which is not great (any suggestions or PR's to fix this while still running integration tests under CI with full Rails app).

Tests are in rspec, run tests simply with `./bin/rspec`.

We use [appraisal](https://github.com/thoughtbot/appraisal) to test with multiple rails versions, including on travis. Locally you can run `bundle exec appraisal rspec` to run tests multiple times for each rails version, or eg `bundle exec appraisal rails-5-1 rspec`. If the `Gemfile` _or_ `Appraisal` file changes, you may need to re-run `bundle exec appraisal install` and commit changes. (Try to put dev dependencies in gemspec instead of Gemfile, but sometimes it gets weird.)

* If you've been switching between rails versions and you get integration test failures, try `rm -rf spec/internal/tmp/cache`. Rails 6 does some things in there apparently not compatible with Rails 5, at least in our setup, and vice versa.

There is a `./bin/console` that will give you a console in the context of attr_json and all it's dependencies, including the combustion rails app, and the models defined there.

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

* [store_model](https://github.com/DmitryTsepelev/store_model) was created after `attr_json`, and has some overlapping functionality.
