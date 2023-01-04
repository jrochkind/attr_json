source 'https://rubygems.org'

# Specify your gem's dependencies in attr_json.gemspec
gemspec

# Dependencies for testing and development. To let appraisal override them, we
# do NOT put them in group :test,:development -- which anyway doesn't make a
# lot of sense in a gem Gemfile anyway, there is no "production" in a gem Gemfile.
#
# We also have these development dependencies here in the Gemfile instead of the
# gemspec so appraisal can override them from our Appraisal file.

gem 'combustion', '~> 1.1'

# all of rails is NOT a dependency, just activerecord.
# But we use it for integration testing with combustion. Hmm, a bit annoying
# that now our other tests can't be sure they're depending, this might not
# be the way to do it.
gem 'rails'

gem "pg"
gem "rspec-rails", "~> 6.0"
gem "simple_form", ">= 4.0"
gem 'cocoon', ">= 1.2"
gem 'jquery-rails'

# Even though we don't use coffee-script, when running specs, some part of rails
# or other part of our stack is still insisting on requiring it, for reasons we
# don't understand, so we need to depend on it.
gem "coffee-rails"

# We do some tests using cocoon via sprockets, which needs sprockets-rails,
# which is not automatically available in Rails 7. We add it explicitly,
# which will duplciate dependences in rails pre-7, but add for rails 7. Not sure
# the future of cocoon in general. https://github.com/nathanvda/cocoon/issues/555
gem "sprockets-rails"


gem 'capybara', "~> 3.0"
gem 'webdrivers', '~> 5.0'
gem "selenium-webdriver"

gem "byebug"


