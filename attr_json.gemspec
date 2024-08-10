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
Typed and cast like Active Record. Supporting nested models, dirty tracking, some querying
(with postgres jsonb contains), and working smoothy with form builders.

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

  spec.required_ruby_version = '>= 2.6.0'

  # This conditional is only to get CI to work on versions of Rails other than
  # we release with. The gem should never be released without the activerecord
  # dependency included just as it is here, should never be released
  # from an env tht has any of these variables set.
  unless ENV['APPRAISAL_INITIALIZED'] || ENV["TRAVIS"] || ENV['CI']
    spec.add_runtime_dependency "activerecord", ">= 6.0.0", "< 8"
  end

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake", ">= 10.0"
  spec.add_development_dependency "rspec", "~> 3.7"
  spec.add_development_dependency "yard-activesupport-concern"
  spec.add_development_dependency "appraisal", "~> 2.2"

  # Working around annoying issue in selenium 3.x with ruby 3.0.
  # we don't actually use rexml ourselves. selenium 3 is a dependency
  # of webdrivers, and tries to use rexml without depending on it
  # as is needed in ruby 3.
  #
  # https://github.com/SeleniumHQ/selenium/issues/9001
  #
  # if in the future you can remove this dependecy and still have tests pass
  # under ruby 3.x, you're good.
  spec.add_development_dependency "rexml"

  # Used only for Capybara.server in our spec_helper.rb.
  # webrick is no longer included in ruby 3.0, so has to
  # be expressed as a dependecy, unless we switch
  # capybara to use alternate webserver.
  spec.add_development_dependency "webrick", "~> 1.0"
end
