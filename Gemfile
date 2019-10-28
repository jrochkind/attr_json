source 'https://rubygems.org'

# Specify your gem's dependencies in attr_json.gemspec
gemspec

# Dependencies for testing and development. To let appraisal override them, we
# do NOT put them in group :test,:development -- which anyway doesn't make a
# lot of sense in a gem Gemfile anyway, there is no "production" in a gem Gemfile.
#
# We also have these development dependencies here in the Gemfile instead of the
# gemspec so appraisal can override them from our Appraisal file.

gem 'combustion', '~> 0.9.0'

# all of rails is NOT a dependency, just activerecord.
# But we use it for integration testing with combustion. Hmm, a bit annoying
# that now our other tests can't be sure they're depending, this might not
# be the way to do it.
gem 'rails'

# We should not really need to mention railties, it's already a dependency of
# rails, but seems to be necessary to get around some mystery bug in bundler
# dependency resolution.
gem 'railties'

gem "pg"
gem "rspec-rails", "~> 3.7"
gem "simple_form", ">= 4.0"
gem 'cocoon', ">= 1.2"
gem 'jquery-rails'

gem 'capybara', "~> 3.0"
gem 'webdrivers', '~> 4.0'
gem "selenium-webdriver"

gem "byebug"


