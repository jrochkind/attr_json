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

end

appraise "rails-edge" do
  gem 'combustion', "~> 1.0"

  gem "rails", git: "https://github.com/rails/rails.git", branch: "main"
  gem "pg", "~> 1.0"

  # Current rails 7 master doesn't have sprockets-rails as a dependency.
  # We don't actually USE sprockets, but we're using "combustion"
  # gem for rails app setup, which is assumign it. So.
  gem "sprockets-rails"
end
