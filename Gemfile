# A sample Gemfile
source 'https://rubygems.org'

ruby '2.2.2'

gem 'travis-core',        github: 'AVGTechnologies/travis-core'
gem 'travis-config',      github: 'final-ci/travis-config'
gem 'travis-support',     github: 'final-ci/travis-support'
gem 'test-aggregation',   github: 'final-ci/test-aggregation'
gem 'travis-sidekiqs',    github: 'final-ci/travis-sidekiqs',   require: nil
gem 'sidekiq-status',     github: 'utgarda/sidekiq-status',     ref: 'e77d5d'
gem 'tsd_utils',          git: 'git@github.com:AVGTechnologies/tsd_utils.git'

gem 'pg'
gem 'connection_pool'
gem 'bunny'

gem 'rack'
gem 'rack-contrib'
gem 'sinatra',            '~> 1.4.6', require: 'sinatra/base' # see https://github.com/resque/resque/issues/934
gem 'rack-cache'
gem 'sinatra-contrib',    '~> 1.4.4'
gem 'puma'

gem 'sentry-raven'
gem 'metriks'

gem 'metriks-librato_metrics'
gem 'micro_migrations'

gem 'activesupport'

group :test do
  gem 'rspec'
  gem 'factory_girl',     '~> 2.6.0'
  gem 'database_cleaner', '~> 1.4.1'
  gem 'fakefs',           require: nil
end

group :development do
  gem 'rerun'
end

gem 'stash-client'
