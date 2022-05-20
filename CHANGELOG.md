# Changelog
Notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased](https://github.com/jrochkind/attr_json/compare/v1.4.0...HEAD)


## [3.0.0]

### Changed

* We now create Rails Attribute cover for all attr_json attributes.  The `rails_attribute` param to `attr_json` or `attr_json_config` no longer exists.  https://github.com/jrochkind/attr_json/pull/117 and https://github.com/jrochkind/attr_json/pull/158

* Drop Rails earlier than 6.0 and ruby earlier than 2.6. https://github.com/jrochkind/attr_json/pull/155

* Array types now default to an empty array. If you'd like to turn that off, you can use the somewhat odd `default: AttrJson::AttributeDefinition::NO_DEFAULT_PROVIDED` on attribute definiton. Thanks @g13ydson for suggestion. https://github.com/jrochkind/attr_json/pull/161

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
