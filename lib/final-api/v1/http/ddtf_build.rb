require 'active_support/core_ext/string/inflections'
require 'test_aggregation'

module FinalAPI
  module V1
    module Http
      class DDTF_Build

        include ::Travis::Api::Formats

        attr_reader :build, :commit, :request

        BUILD_STATE2API_V1STATUS = {
          'created' => 'Configured',
          'received' => 'Pending',
          'started' => 'Running',
          'passed' => 'Finished',
          'failed' => 'Finished',
          'canceled' => 'Stopped',
          'errored' => 'Aborted',
          '' => 'Unknown'
        }

        STATE2API_V1STATUS = {
          # designed states in final-ci
          'created' => 'NotSet',
          'blocked' => 'NotTested',
          'passed' => 'Passed',
          'failed' => 'Failed',
          # fix for Test aggregation step result re-writing
          'nottested' => 'NotTested',
          'knownbug' => 'KnownBug',
          'skipped' => 'Skipped',
           # data status re-write after node properly sends data
          'known_bug' => 'KnownBug',
          'not_performed' => 'NotPerformed'
          # 'skipped' => 'Skipped'
        }

        def initialize(build, options = {})
          @build = build
          @commit = build.commit
          @request = build.request
        end

        #statuses are mapped in app/common/filters/status-class-filter.js on AtomUI side
        def test_data
          config = build.config

          {
            'id' => build.id,
            'buildId' => build.id,
            'ddtfUuid' => config[:ddtf_uuid] ||
              config[:ddtf_uid] ||
              config[:ddtfUuid],
            'name' => build.name,
            'description' => config[:description],
            'branch' => config[:branch],
            'build' => build.build_info,

            'status' => BUILD_STATE2API_V1STATUS[build.state.to_s.downcase],
            'strategy': config[:strategy],
            'email': config[:email],

            'started': build.created_at.to_s,  #TODO remove to_s
            'enqueued': build.started_at.to_s, #TODO remove to_s
            'startedBy': build.owner.try(:name).to_s,

            'stopped': build.state == 'canceled',
            'stoppedBy': build.stopped_by.try(:name), # TODO

            'isTsd': true,
            'checkpoints':    config[:checkpoints] || false,
            'debugging':      config[:debugging] || false,
            'buildSignal':    config[:build_signal],
            'scenarioScript': config[:scenario_script],
            'packageSource':  config[:package_source],
            'executionLogs':  request.try(:message).to_s,
            'stashTSD':       config[:tsd_content],
            'runtimeConfig':  ddtf_runtimeConfig,

            'parts': parts_status,
            'tags': [],

            'result': build.state,

            #progress bar:
            'results': ddtf_results_distribution
          }
        end

        def parts_data
          ddtf_test_aggregation_result.as_json
        end

        def atom_response
          {
            id: build.id.to_s, # BAMBOO expects string in v1 API
            name: build.name,
            build: build.build_info,
            result: 'NotSet',
            results:
            {
              Type: 'NotSet',
              Value: 1.0
            },
            enqueued: Time.now
          }
        end

        private

        # returns hash of results of all test
        def ddtf_results_distribution
          res = ddtf_test_aggregation_result.results_hash
          %w(
            NotPerformed notPerformed not_performed
            Skipped skipped
          ).each do |not_reported_state|
            res.delete not_reported_state
          end

          sum = res.values.inject(0.0) { |s,i| s + i }
          res.inject([]) do |s, (result, count)|
            s << { 'type' => result, 'value' => count.to_f / sum }
          end
        end

        def ddtf_runtimeConfig
          build.config[:runtimeConfig] || []
        end

        def parts_status
          build.parts_groups.map do |part_name, jobs|
            {
              name: part_name,
              result: ddtf_test_aggregation_result.result(part: part_name)
            }
          end
        end

        def state2api_v1status(step)
          return 'NotSet' if step[:data]['status'].nil? && step[:result] == 'pending'
          STATE2API_V1STATUS[step[:data]['status'] || step[:result]]
        end

        def ddtf_v1_overall_status(results)
          all_states = results.each_with_object([]) do |(k, v), result|
            result << state2api_v1status(v)
          end.uniq

          return 'Skipped' if all_states.include? 'Skipped'
          return 'Failed' if all_states.include? 'Failed'
          return 'Invalid' if all_states.include? 'Invalid'
          return 'NotTested' if all_states.include? 'NotTested'
          return 'KnownBug' if all_states.include? 'KnownBug'
          return 'NotSet' if all_states.include? 'NotSet'
          return 'Passed' if all_states.include? 'Passed'

          'NotPerformed'
        end

        def ddtf_test_aggregation_result
          return @ddtf_test_aggregation_result if (
            defined?(@ddtf_test_aggregation_result) &&
            @ddtf_test_aggregation_result
          )

          @ddtf_test_aggregation_result ||= TestAggregation::BuildResults.new(
            build,
            ->(job) { job.ddtf_part },
            ->(job) { job.ddtf_machine },
            lambda do |step_result|
              {
                id: step_result.__id__,
                description: step_result.name,
                machines: step_result.results.inject({}) do |s, (k, v)|
                  s[k] = { result: state2api_v1status(v), message: '', resultId: v[:uuid] }
                  s
                end.merge(
                  all: {
                    result: step_result.results.all? do |(_k, v)|
                      ['passed', 'pending'].include?(v[:result])
                    end ? 'Passed' : ddtf_v1_overall_status(step_result.results)
                  }
                )
              }
            end,
            ->(step_result) {
              result = (step_result['data'] and step_result['data']['status']).try(:camelcase)
              result ||= step_result['result'].downcase
            }
          )
          build.matrix.each do |job|
            StepResult.where(job_id: job.id).order('id desc').each do |sr|
              @ddtf_test_aggregation_result.parse(sr.data)
            end
          end
          @ddtf_test_aggregation_result
        end

      end
    end
  end
end
