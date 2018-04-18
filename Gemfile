source 'https://rubygems.org'

# Specify your gem's dependencies in json_attribute.gemspec
gemspec

# for our integration test in a real rails env, we add em in development too,
# so we can bring up the app or a console in development to play with it.
group :test, :development do
  gem 'combustion', '~> 0.9.0'
  # all of rails is NOT a dependency, just activerecord.
  # But we use it for integration testing with combustion. Hmm, a bit annoying
  # that now our other tests can't be sure they're depending, this might not
  # be the way to do it.
  gem "rails", ENV["RAILS_GEM"] && ENV["RAILS_GEM"].split(",")
  gem "rspec-rails", "~> 3.7"
  gem "simple_form", ">= 4.0"
  gem 'cocoon', ">= 1.2"
  gem 'jquery-rails'
  gem 'capybara', "~> 3.0"
  gem "chromedriver-helper"
  gem "selenium-webdriver"
end

if ENV['RAILS_GEM']
  gem "activerecord", ENV['RAILS_GEM'].split(",")

  # This shouldn't really be needed, but seems to maybe be a bundler bug,
  # this makes standalone_migrations dependencies resolve properly even when our
  # RAILS_REQ is for 5.2.0.rc2. If in the future you delete this and everything
  # still passes, feel free to remove.
  gem "railties", ENV['RAILS_GEM'].split(",")
end

# Rails 5.0 won't work with pg 1.0, but that isn't actually in it's gemspec,
# workaround, specify PG_GEM too with RAILS_GEM including 5.0.
if ENV['PG_GEM']
  gem "pg", ENV['PG_GEM']
end

gem "byebug"
