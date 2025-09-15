# Changelog
Notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [Unreleased](https://github.com/jrochkind/attr_json/compare/v2.4.0...HEAD)

### Fixed

*

*

*

### Added

*

*

### Changed

*

*

*

## [2.5.1](https://github.com/jrochkind/attr_json/compare/v2.5.0...v2.5.1)

## Fixed

* Fixed bug where date/datetime types required db to exist on app boot. https://github.com/jrochkind/attr_json/pull/242 Thanks @jNicker


## [2.5.0](https://github.com/jrochkind/attr_json/compare/v2.4.0...v2.5.0)

## Added

* Allow Rails 8.0 in gemspec (no code changes required to support) https://github.com/jrochkind/attr_json/pull/236

## [2.4.0](https://github.com/jrochkind/attr_json/compare/v2.3.1...v2.4.0)

### Added

* Allow Rails 7.2 in gemspec (no code changes required to support) https://github.com/jrochkind/attr_json/pull/228

## [2.3.1](https://github.com/jrochkind/attr_json/compare/v2.3.0...v2.3.1)

### Fixed

* Keep nested model validation working in Rails post-7.1, by no longer trying to re-use ActiveRecord::Validations::AssociatedValidator, instead supplying our own custom code. https://github.com/jrochkind/attr_json/pull/220

* Validate PolymorphicModel instances. https://github.com/jrochkind/attr_json/pull/225 Thanks @LyricL-Gitster


## [2.3.0]((https://github.com/jrochkind/attr_json/compare/v2.2.0...v2.3.0))


### Changed

* Avoid private ActiveRecord API when lazily registering container attributes. (Compat with Rails post 7.1) https://github.com/jrochkind/attr_json/pull/214

* Freeze more strings to reduce String allocations https://github.com/jrochkind/attr_json/pull/216

## [2.2.0](https://github.com/jrochkind/attr_json/compare/v2.1.0...v2.2.0)

### Added

* Test and allow Rails 7.1 https://github.com/jrochkind/attr_json/pull/208 Thanks @JoeSouthan


## [2.1.0](https://github.com/jrochkind/attr_json/compare/v2.0.1...v2.1.0)

### Added

* Support for `store_key` in models used with polymorphic model feature. https://github.com/jrochkind/attr_json/pull/206 . Thanks @rdubya


## [2.0.1](https://github.com/jrochkind/attr_json/compare/v2.0.0...v2.0.1)


### Fixed

* You can now do a specified ActiveRecord `.select` without your json containers, to fetch an object with other attributes that you can access. https://github.com/jrochkind/attr_json/pull/193

### Changed

* Refactor #attr_json_sync_to_rails_attributes for slightly improved performance. https://github.com/jrochkind/attr_json/pull/192

* Safety guard in sync_to_rails_attributes against unknown edge case where container is nil https://github.com/jrochkind/attr_json/pull/194


## [2.0.0](https://github.com/jrochkind/attr_json/compare/v1.5.0...v2.0.0)

While it has some backwards incompat changes, this is expected not to be a challenging upgrade, please let us know by filing an issue if it's giving you troubles, maybe we can make things easier for you. No changes to data stored in your DB should be needed when upgrading, the persisted data should be compatible between 1.x and 2.x.

### Removed

* `AttrJson::Record::Dirty` has been removed, along with the `#attr_json_changes` method. You should now be able to just use standard ActiveRecord dirty tracking with attr_json attributes. https://github.com/jrochkind/attr_json/pull/163 (AttrJson::Record::Dirty was actually badly broken, as reported by @bemueller at https://github.com/jrochkind/attr_json/issues/148)

* The `rails_attribute` param to `attr_json` or `attr_json_config` no longer exists. We now always create rails attributes for AttrJson::Record attributes. https://github.com/jrochkind/attr_json/pull/117 and https://github.com/jrochkind/attr_json/pull/158

### Changed

* We now create Rails Attribute cover for all attr_json attributes, and we do a better job of keeping the Rails attribute values sync'd with attr_json values.   https://github.com/jrochkind/attr_json/pull/117, https://github.com/jrochkind/attr_json/pull/158, and https://github.com/jrochkind/attr_json/pull/163

* Drop support for Rails earlier than 6.0 and ruby earlier than 2.7. https://github.com/jrochkind/attr_json/pull/155 https://github.com/jrochkind/attr_json/pull/174

* Array types now default to an empty array. If you'd like to turn that off, you can use the somewhat odd `default: AttrJson::AttributeDefinition::NO_DEFAULT_PROVIDED` on attribute definiton. Thanks @g13ydson for suggestion. https://github.com/jrochkind/attr_json/pull/161

* time or datetime types used to truncate all fractional seconds to 0. Now they properly allow precision of `ActiveSupport::JSON::Encoding.time_precision` (normally three decimal places, ie milliseconds). And by default the Type::Value's are set to proper precision for cast too. https://github.com/jrochkind/attr_json/pull/173

* AttrJson::Models are serialized without nil values in the hash, for more compact representations. This is only done for attributes without defaults. This behavior can be disabled/altered when specifying the type. https://github.com/jrochkind/attr_json/pull/175

* config default_accepts_nested_attributes will only apply nested attributes to suitable attribute types (array or nested model), the default won't apply to inapplicable types. https://github.com/jrochkind/attr_json/pull/178

### Added

* ActiveRecord-style "timezone-aware attribute" conversion now works properly, in both AttrJson::Record and (similarly) AttrJson::Model. https://github.com/jrochkind/attr_json/pull/164

### Fixed

* the `AttrJson::Type::Array` type used for our array types was not properly tracking in-place mutation changes. Now it is https://github.com/jrochkind/attr_json/pull/163

* Default nested model validation should allow nils in arrays of models. https://github.com/jrochkind/attr_json/pull/177



## [1.5.0](https://github.com/jrochkind/attr_json/compare/v1.4.1...v1.5.0)

### Added

* AttrJson::Model#dup will properly deep-dup attributes https://github.com/jrochkind/attr_json/pull/169

* AttrJson::Model#freeze will freeze attributes -- but not deep-freeze. https://github.com/jrochkind/attr_json/pull/169

* AttrJson::Model has some methods conventional in ActiveModel classes: Klass.attribute_types, Klass.attribute_names, and instance.attribute_names. https://github.com/jrochkind/attr_json/pull/169



## [1.4.1](https://github.com/jrochkind/attr_json/compare/v1.4.0...v1.4.1)

### Fixed

* Fixed an obscure bug involving a conflict between attribute defaults and accepts_nested_attributes, in which defaults could overwrite assigned attributes. The `.fill_in_defaults` class method, which was never intended as public API and was commented accordingly, is gone. https://github.com/jrochkind/attr_json/pull/160

## [1.4.0](https://github.com/jrochkind/attr_json/compare/v1.3.0...v1.4.0)

### Changed

* When using store_key feature on an AttrJson::Model, you should not be able to pass in the store_key as a key in initializer or assign_attributes. It was really a bug that this ended up mapped to attribute this way, which could cause a problem in some cases; but calling it out in Changed section because if you were accidentally relying on it, it may appear as a backwards incompat to you. https://github.com/jrochkind/attr_json/pull/125

* Rails 7.0.0 allowed by gemspec and tested in CI

### Fixed

* polymorphic single type can be set to nil https://github.com/jrochkind/attr_json/pull/115
* polymorphic models can be serialized from hash in container attribute. Thanks @machty. https://github.com/jrochkind/attr_json/pull/123
* fix bug with deserialization of nested attributes that have types that apply different serialization vs cast logic. Thanks @bradleesand. https://github.com/jrochkind/attr_json/pull/125

## [1.3.0](https://github.com/jrochkind/attr_json/compare/v1.2.0...v1.3.0)

### Added

* Gemspec allows use with ActiveRecord 6.1.x

## [1.2.0](https://github.com/jrochkind/attr_json/compare/v1.1.0...v1.2.0)

### Added

* attr_json_config(bad_cast: :as_nil) to avoid raising on data that can't be cast to a
  AttrJson::Model, instead just casting to nil. https://github.com/jrochkind/attr_json/pull/95

* Documented and tested support for using ActiveRecord serialize to map one AttrJson::Model
to an entire column on it's own. https://github.com/jrochkind/attr_json/pull/89 and
https://github.com/jrochkind/attr_json/pull/93

* Better synchronization with ActiveRecord attributes when using rails_attribute:true, and a configurable true default_rails_attribute.  Thanks @volkanunsal . https://github.com/jrochkind/attr_json/pull/94

### Changed

* AttrJson::Model#== now requires same class for equality. And doesn't raise on certain arguments. https://github.com/jrochkind/attr_json/pull/90 Thanks @caiofilipemr for related bug report.

## [1.1.0](https://github.com/jrochkind/attr_json/compare/v1.0.0...v1.1.0)

### Added

* not_jsonb_contains query method, like `jsonb_contains` but negated. https://github.com/jrochkind/attr_json/pull/85
