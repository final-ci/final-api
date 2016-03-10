$: << 'lib'

require 'bundler/setup'
require 'final-api/config'
require 'travis'

require 'active_record'

require 'raven'
require 'metriks'
require 'metriks/reporter/graphite'

require 'final-api/ddtf'
require 'final-api/model_extensions'

require 'test_aggregation'

require 'sidekiq'
require 'travis-sidekiqs'
require 'sidekiq-status'
require 'travis/support/amqp'

module FinalAPI
  class << self
    def config
      @confg ||= FinalAPI::Config.load
    end

    def logger
      Travis.logger
    end

    def logger=(l)
      Travis.logger = l
    end

    def env
      Travis.env
    end

    def setup
      Travis.logger.info "Starting Final-CI API in #{Travis.env}"

      Travis::Database.connect
      Log.establish_connection 'logs_database'
      Log::Part.establish_connection 'logs_database'
      StepResult.establish_connection 'test_results_database'

      TestAggregation::BuildResults.sum_results = method(:custom_sum_results)

      Sidekiq.configure_server do |config|
        config.redis = Travis.config.redis.merge(namespace: Travis.config.sidekiq.namespace)
        config.server_middleware do |chain|
          chain.add Sidekiq::Status::ServerMiddleware, expiration: 30.minutes # default
        end
        config.client_middleware do |chain|
          chain.add Sidekiq::Status::ClientMiddleware
        end
      end

      Travis::Async::Sidekiq.setup(Travis.config.redis.url, Travis.config.sidekiq)
      Sidekiq.configure_client do |config|
        config.client_middleware do |chain|
          chain.add Sidekiq::Status::ClientMiddleware
        end
      end

      Travis::Amqp.config = Travis.config.amqp

      Travis::Metrics.setup
      Travis::Notification.setup

      if FinalAPI.config.sentry_dsn
        ::Raven.configure do |config|
          config.dsn = FinalAPI.config.sentry_dsn
          config.environments = %w[ production ]
          config.current_environment = FinalAPI.env
          config.excluded_exceptions = %w{Siatra::NotFound}
        end
      end

      Metriks::Reporter::Graphite.new(
        config.graphite.host,
        config.graphite.port,
        config.graphite.options || {}
      ) if config.graphite
    end

    private

    def custom_sum_results(results)
      r = results.reject { |_res, count| count <= 0 }.keys.uniq.compact

      # when 'errored' step exists
      return 'errored' if r.include?('errored')

      # when 'failed' step exists
      return 'failed' if r.include?('failed')

      # when all are 'created', then created
      # when all are 'pending', then pending
      return r.first if r.size == 1 && TestAggregation::StepResult::RESULTS.include?(r.first)

      return 'passed' if
        r.include?('passed') &&
        (r - %w(passed pending skipped notPerformed knownBug)).empty?

      # when 'created' exists, e.g. test is still running
      return 'created' if r.include?('created')

      # when no results
      return 'errored' if r.empty?

      fail "Unknown result for: #{r.inspect}"
    end
  end
end
