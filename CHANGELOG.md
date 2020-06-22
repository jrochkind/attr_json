# Changelog
Notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased](https://github.com/jrochkind/attr_json/compare/v1.1.0...HEAD)

### Added

* attr_json_config(bad_cast: :as_nil) to avoid raising on data that can't be cast to a
  AttrJson::Model, instead just casting to nil. https://github.com/jrochkind/attr_json/pull/95

* Documented and tested support for using ActiveRecord serialize to map one AttrJson::Model
to an entire column on it's own. https://github.com/jrochkind/attr_json/pull/89

* Better synchronization with ActiveRecord attributes when using rails_attribute:true, and a configurable true default_rails_attribute.  Thanks @volkanunsal . https://github.com/jrochkind/attr_json/pull/94

### Changed

* AttrJson::Model#== now requires same class for equality. And doesn't raise on certain arguments. https://github.com/jrochkind/attr_json/pull/90 Thanks @caiofilipemr for related bug report.

## [1.1.0](https://github.com/jrochkind/attr_json/compare/v1.0.0...v1.1.0)

### Added

* not_jsonb_contains query method, like `jsonb_contains` but negated. https://github.com/jrochkind/attr_json/pull/85
