source 'https://rubygems.org'

# Specify your gem's dependencies in json_attribute.gemspec
gemspec

gem 'combustion', '~> 0.9.0', :group => :test

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
