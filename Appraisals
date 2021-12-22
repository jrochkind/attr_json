appraise "rails-5-0" do
  gem 'combustion', '~> 0.9.0'

  gem "rails", "~> 5.0.0"

  # rails 5.1+ includes it by default, but rails 5.0 needs it:
  gem 'rails-ujs', require: false

  # Rails 5 won't work with pg 1.0 even though it doesn't say so
  gem "pg",  "~> 0.18"
end

appraise "rails-5-1" do
  gem 'combustion', '~> 0.9.0'

  gem "rails", "~> 5.1.0"

  gem "pg", "~> 1.0"
end

appraise "rails-5-2" do
  gem 'combustion', '~> 0.9.0'

  gem "rails", "~> 5.2.0"
  gem "pg", "~> 1.0"
end

appraise "rails-6-0" do
  gem 'combustion', "~> 1.0"

  gem "rails", ">= 6.0.0", "< 6.1"
  gem "pg", "~> 1.0"
end

appraise "rails-6-1" do
  gem 'combustion', "~> 1.0"

  gem "rails", "~> 6.1.0"
  gem "pg", "~> 1.0"
end

appraise "rails-7-0" do
  gem 'combustion', "~> 1.0"

  gem "rails", "~> 7.0.0"
  gem "pg", "~> 1.0"

  # We do some tests using cocoon, currently via sprockets-rails,
  # which is not automatically available in Rails 7.  Not sure
  # the future of cocoon in general. https://github.com/nathanvda/cocoon/issues/555
  gem "sprockets-rails"
end

appraise "rails-edge" do
  gem 'combustion', "~> 1.0"

  gem "rails", git: "https://github.com/rails/rails.git", branch: "main"
  gem "pg", "~> 1.0"

  # We do some tests using cocoon, currently via sprockets-rails,
  # which is not automatically available in Rails 7.  Not sure
  # the future of cocoon in general. https://github.com/nathanvda/cocoon/issues/555
  gem "sprockets-rails"
end
