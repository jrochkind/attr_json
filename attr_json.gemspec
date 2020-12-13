# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'attr_json/version'

Gem::Specification.new do |spec|
  spec.name          = "attr_json"
  spec.version       = AttrJson::VERSION
  spec.authors       = ["Jonathan Rochkind"]
  spec.email         = ["jonathan@dnil.net"]

  spec.summary       = %q{ActiveRecord attributes stored serialized in a json column, super smooth.}
  spec.description   = %q{ActiveRecord attributes stored serialized in a json column, super smooth.
For Rails 5.0, 5.1, or 5.2. Typed and cast like Active Record. Supporting nested models,
dirty tracking, some querying (with postgres jsonb contains), and working smoothy with form builders.

Use your database as a typed object store via ActiveRecord, in the same models right next to
ordinary ActiveRecord column-backed attributes and associations. Your json-serialized attr_json
attributes use as much of the existing ActiveRecord architecture as we can.}
  spec.homepage      = "https://github.com/jrochkind/attr_json"
  spec.license       = "MIT"
  spec.metadata      = {
    "homepage_uri"      => "https://github.com/jrochkind/attr_json",
    "source_code_uri"   => "https://github.com/jrochkind/attr_json"
  }

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  # if spec.respond_to?(:metadata)
  #   spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  # else
  #   raise "RubyGems 2.0 or newer is required to protect against " \
  #     "public gem pushes."
  # end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.required_ruby_version = '>= 2.4.0'

  # Only to get CI to work on versions of Rails other than we release with,
  # should never release a gem with RAILS_GEM set!
  unless ENV['APPRAISAL_INITIALIZED'] || ENV["TRAVIS"] || ENV['CI']
    spec.add_runtime_dependency "activerecord", ">= 5.0.0", "< 6.2"
  end

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", ">= 10.0"
  spec.add_development_dependency "rspec", "~> 3.7"
  spec.add_development_dependency "database_cleaner", "~> 1.5"
  spec.add_development_dependency "yard-activesupport-concern"
  spec.add_development_dependency "appraisal", "~> 2.2"
end
