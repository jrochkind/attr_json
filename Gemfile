source 'https://rubygems.org'

# Specify your gem's dependencies in attr_json.gemspec
gemspec

# for our integration test in a real rails env, we add em in development too,
# so we can bring up the app or a console in development to play with it.
group :test, :development do
  if ENV['RAILS_GEM'] == "edge"
    # we need unreleased combustion
    gem 'combustion', git: "https://github.com/pat/combustion.git"
  else
    gem 'combustion', '~> 0.9.0'
  end

  # all of rails is NOT a dependency, just activerecord.
  # But we use it for integration testing with combustion. Hmm, a bit annoying
  # that now our other tests can't be sure they're depending, this might not
  # be the way to do it.
  if ENV['RAILS_GEM'] == "edge"
    gem "rails", git: "https://github.com/rails/rails.git", branch: "master"
    gem "railties"

    # I think we need coffee-rails as an explicit dependency just for weird transistory
    # reasons on rails edge being in progress. We're not actually using it at all.
    gem 'coffee-rails'
  else
    gem "rails", ENV["RAILS_GEM"] && ENV["RAILS_GEM"].split(",")

    gem "activerecord", ENV["RAILS_GEM"] && ENV['RAILS_GEM'].split(",")
    # This shouldn't really be needed, but seems to maybe be a bundler bug,
    # this makes standalone_migrations dependencies resolve properly even when our
    # RAILS_REQ is for 5.2.0.rc2. If in the future you delete this and everything
    # still passes, feel free to remove.
    gem "railties", ENV["RAILS_GEM"] && ENV['RAILS_GEM'].split(",")
  end

  # Rails 5.0 won't work with pg 1.0, but that isn't actually in it's gemspec.
  # So we specify a compatible PG_GEM spec when testing with rails 5.
  ENV['PG_GEM'] ||= ">= 0.18.1"
  gem "pg", ENV['PG_GEM']

  gem "rspec-rails", "~> 3.7"
  gem "simple_form", ">= 4.0"
  gem 'cocoon', ">= 1.2"
  gem 'jquery-rails'
  gem 'capybara', "~> 3.0"
  gem "chromedriver-helper"
  gem "selenium-webdriver"
  # rails 5.1+ includes it by default, but rails 5.0 needs it:
  gem 'rails-ujs', require: false

  gem 'capybara-screenshot', :group => :test
end

gem "byebug"
