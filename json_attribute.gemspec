# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'json_attribute/version'

Gem::Specification.new do |spec|
  spec.name          = "json_attribute"
  spec.version       = JsonAttribute::VERSION
  spec.authors       = ["Jonathan Rochkind"]
  spec.email         = ["jonathan@dnil.net"]

  spec.summary       = %q{experimental in progress}
  spec.description   = %q{Typed, structured, and compound/nested attributes backed by ActiveRecord
and Postgres Jsonb. With some query support.  Or, we could say, "Postgres
jsonb via ActiveRecord as a typed, object-oriented document store." A basic
one anyway. We intend JSON attributes to act consistently, with no surprises,
and just like you expect from ordinary ActiveRecord, by using as much of
existing ActiveRecord architecture as we can.}
  #spec.homepage      = "TODO: Put your gem's website or public repo URL here."
  spec.license       = "MIT"

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "activerecord", ">= 5.0.0", "< 5.3"
  spec.add_runtime_dependency "pg", ">= 0.18.1"

  spec.add_development_dependency "bundler", "~> 1.14"
  spec.add_development_dependency "rake", ">= 10.0"
  spec.add_development_dependency "rspec", "~> 3.5"
  spec.add_development_dependency "database_cleaner", "~> 1.5"
end
