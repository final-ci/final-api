require 'final-api/ext/hash'

module FinalAPI
  module Endpoint
    module DDTF
      # Auxiliary routines for ddtf routes
      class DdtfHelpers
        class << self

          public

          def build_config(test_data, enqueue_data)
            {
              language: 'tsd',
              git:
              {
                no_clone: true
              },
              name: enqueue_data.tsd['name'],
              description: test_data.get_ikey('Description'),
              branch: enqueue_data.package_source,
              build: test_data.get_ikey('Build'),
              strategy: test_data.get_ikey('Strategy') || enqueue_data.tsd['defaultStrategy'],
              email: test_data.get_ikey('Email'),
              checkpoint: test_data.get_ikey('Checkpoints'),
              scenarioScript: test_data.get_ikey('ScenarioScript'),
              stashTsd: test_data.get_ikey('StashTSD'),
              tsdContent: enqueue_data.tsd,
              runtimeConfig: test_data.get_ikey('RuntimeConfigFields'),
              ddtfUuid: test_data.get_ikey('Id')
            }
          end

          def create_build(repository_id, user_id, config)
            ActiveRecord::Base.transaction do
              repo, commit, request = setup_build(repository_id, user_id)
              owner = request.owner

              runtime_config = config && config[:runtimeConfig]
              build = Build.create!(
                repository: repo,
                commit: commit,
                request: request,
                config: config,
                owner: owner,
                name: config && config[:name],
                build_info: config && config[:build],
                proton_id: get_field_from_runtime_config(runtime_config, 'protonid')
              )

              clean_build_matrix(build)

              build
            end
          end

          def setup_build(repository_id, user_id)
            repository = Repository.find(repository_id) || Repository.first # FIXME: Proper repository retrieval
            commit = repository.commits.create!(
              commit: SecureRandom.hex(20), branch: 'branch', committed_at: Time.now) # FIXME: Proper commit retrieval
            request = Request.create!(
              repository: repository, owner: User.find(user_id))

            [repository, commit, request]
          end

          def clean_build_matrix(build)
            build.matrix.destroy_all
            build.cached_matrix_ids = nil
            # build.start(started_at: Time.now.utc)
            build.save!
          end

          private

          def get_field_from_runtime_config(runtime_config, field_name)
            return if runtime_config.nil?

            if Hash === runtime_config
              field = runtime_config.find do |definition, value|
                definition.to_s.try(:downcase) == field_name
              end
              return unless field
              return field.last
            else
              field = runtime_config.find do |item|
                item[:definition].try(:downcase) == field_name
              end
              return unless field
              return field[:value]
            end
          end
        end
      end
    end
  end
end
