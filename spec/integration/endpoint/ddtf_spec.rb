require 'final-api/app'

describe 'DDTF' do
  include Rack::Test::Methods

  def app
    FinalAPI::App
  end

  let(:post_payload) { { file: { source: {} }.to_json }.to_json }
  let!(:user) { Factory(:user) }

  let(:headers) do
    {
      'HTTP_ACCEPT' => 'application/json',
      'HTTP_USERNAME' => user.login,
      'HTTP_NAME' => user.login,
      'HTTP_AUTHENTICATIONTOKEN' => 'secret'
    }
  end

  before do
    allow_any_instance_of(TsdUtils::EnqueueData).to receive(:build_all)
    allow_any_instance_of(TsdUtils::EnqueueData).to receive(:tsd) { { 'source' => {} } }
    allow_any_instance_of(Travis::Amqp::Publisher).to receive(:publish)

    allow(FinalAPI.config).to receive_message_chain(:tsd_utils, :clusters) { {} }
    allow(FinalAPI.config.ddtf).to receive(:email_domain) { 'mail.com' }
  end

  context 'POST /ddtf/builds' do
    let(:repository) { Factory(:repository) }
    let(:config) do
      {
        language: 'tsd',
        env: ['MACHINE=x764 PART=1', 'MACHINE=8x64 PART=1'],
        os: 'windows'
      }
    end
    let(:payload) do
      {
        user_id: user.id,
        repository_id: repository.id,
        config: config
      }
    end

    it "create build and return its json" do
      post '/ddtf/builds', payload, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response['config']['language']).to eq('tsd')
    end

    it "set build to 'started' state" do
      post '/ddtf/builds', payload, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response['state']).to eq('created')
    end

    it 'returns 404 when user and repository not specified' do
      post '/ddtf/builds', {}, headers
      expect(last_response.status).to eq(404)
    end

    it 'returns 404 when user and repository not exists' do
      post '/ddtf/builds', { user_id: 100_000, repository_id: 100_000 }, headers
      expect(last_response.status).to eq(404)
    end
  end

  context 'POST /ddtf/builds/:build_id/jobs' do
    let(:build) { Factory(:build) }
    let(:repository) { Factory(:repository) }
    let(:config) do
      {
        language: 'tsd',
        env: 'MACHINE=x764 PART=1',
        os: 'windows'
      }
    end
    it "creates job and returns its json" do
      post "/ddtf/builds/#{build.id}/jobs", { config: config }, headers
      expect(last_response.status).to eq(200)
      result = MultiJson.load(last_response.body)
      expect(result['config']['env']).to eq('MACHINE=x764 PART=1')
      expect(result['config']['os']).to eq('windows')
    end

    it "set job to 'received' state" do
      post "/ddtf/builds/#{build.id}/jobs", { config: config }, headers
      expect(last_response.status).to eq(200)
      result = MultiJson.load(last_response.body)
      expect(result['state']).to eq('received')
    end

    it 'returns 404 when build does not exists' do
      post '/ddtf/builds/1000/jobs', {}, headers
      expect(last_response.status).to eq(404)
    end
  end

  context 'GET /ddtf/tests' do
    it 'returns last 20 builds by default' do
      1.upto(22) do |idx|
        Factory(:build, name: idx.to_s)
      end
      get '/ddtf/tests', {}, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.last['name']).to eq '3'
      expect(response.first['name']).to eq '22'
      expect(response.size).to eq 20
    end

    it 'limit results by limit param' do
      1.upto(3) do |idx|
        Factory(:build, config: { name: idx.to_s })
      end
      get '/ddtf/tests', { limit: 2 }, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.size).to eq 2
    end

    it 'paginate by limit and offset params' do
      1.upto(5) do |idx|
        Factory(:build, name: idx.to_s)
      end
      get '/ddtf/tests', { limit: 2, offset: 2 }, headers
      expect(last_response.status).to eq(200)
      response = MultiJson.load(last_response.body)
      expect(response.last['name']).to eq '2'
      expect(response.first['name']).to eq '3'
      expect(response.size).to eq 2
    end

    describe 'filter by "q" param' do
      let(:user_nomae) { Factory(:user, name: 'noname') }
      let(:user) { Factory(:user, name: 'franta.lopata') }
      let!(:builds) do
        (1..20).map do |idx|
          Factory(:build, name: idx.to_s, owner: user_nomae)
        end
      end
      let!(:user_build) do
        Factory(:build, name: 'user_build', owner: user, stopped_by: user)
      end

      it 'search by \'nam\' and \'name\' keyword with contains operator' do
        get '/ddtf/tests', { q: 'nam: 2' }, headers
        expect(last_response.status).to eq(200)
        response1 = MultiJson.load(last_response.body)
        expect(response1.size).to eq 3 # '2', '12', '20'

        get '/ddtf/tests', { q: 'name: 2' }, headers
        expect(last_response.status).to eq(200)
        response2 = MultiJson.load(last_response.body)
        expect(response2).to eq response1
      end

      it 'search by \'nam\' and \'name\' keyword with = operator' do
        get '/ddtf/tests', { q: 'nam= 2' }, headers
        expect(last_response.status).to eq(200)
        response1 = MultiJson.load(last_response.body)
        expect(response1.size).to eq 1

        get '/ddtf/tests', { q: 'name= 2' }, headers
        expect(last_response.status).to eq(200)
        response2 = MultiJson.load(last_response.body)
        expect(response2).to eq response1
      end

      it 'search by \'startedBy\' keyword with = operator' do
        get '/ddtf/tests', { q: 'startedBy = franta.lopata' }, headers
        expect(last_response.status).to eq(200)
        response1 = MultiJson.load(last_response.body)
        expect(response1.size).to eq 1
      end

      it 'search by \'stoppedBy\' keyword with : operator' do
        get '/ddtf/tests', { q: 'stoppedBy : nta.lopa' }, headers
        expect(last_response.status).to eq(200)
        response1 = MultiJson.load(last_response.body)
        expect(response1.size).to eq 1
      end


      it 'search by combination of keywords' do
        b = builds.last
        get '/ddtf/tests',
            { q: "name : #{b.name} id = \"#{b.id}\"" },
            headers
        response = MultiJson.load(last_response.body)
        expect(response.size).to eq 1
        expect(response.first['id']).to eq b.id
      end

      it 'ignore words without column definition' do
        b = builds.last
        get '/ddtf/tests',
            { q: "name : #{b.name} XXXXX" },
            headers
        response = MultiJson.load(last_response.body)
        expect(response.size).to eq 1
        expect(response.first['id']).to eq b.id
      end
    end

    it 'returns proper structure' do
      build = Factory(:build,
                      config: {
                        name: 'TSD name',
                        description: 'myDescription'
                      },
                      name: 'TSD name'
                     )

      get '/ddtf/tests', {}, headers
      response = MultiJson.load(last_response.body).first
      expected_response = {
        'id' => build.id,
        'name' => 'TSD name',
        'description' => 'myDescription',
        'branch' => nil,
        'build' => nil,
        'status' => 'Finished',
        'strategy' => nil,
        'email' => nil,
        'startedBy' => 'Sven Fuchs',
        'stopped' => false,
        'stoppedBy' => nil,
        'isTsd' => true,
        'checkpoints' => false,
        'buildSignal' => false,
        'scenarioScript' => false,
        'executionLogs' => '',
        'stashTSD' => nil,
        'runtimeConfig' => [],
        'parts' => [{ 'name' => nil, 'result' => 'created' }],
        'tags' => [],
        'result' => 'passed',
        'results' => [{ 'type' => 'created', 'value' => 1.0 }],
        'buildId' => build.id
      }
      expect(response).to include(expected_response)
    end
  end

  describe 'GET /ddtf/tests/:id' do
    before do
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:clusters) { ['cluster'] }
    end

    context 'when build exists' do
      build_id = nil
      before do
        post '/ddtf/tests', post_payload, headers
        build_id = MultiJson.load(last_response.body)['id'].to_s
      end

      it 'returns 200' do
        get "/ddtf/tests/#{build_id}", headers
        expect(last_response.status).to eq(200)
      end
    end

    context 'when build does not exist' do
      it 'returns 404' do
        get '/ddtf/tests/foo', headers
        expect(last_response.status).to eq(404)
      end
    end
  end

  describe 'POST /ddtf/tests/:id/retest' do
    before do
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
      allow_any_instance_of(TsdUtils::EnqueueData).to receive(:clusters) { ['cluster'] }
    end

    let(:build) { Factory(:build) }
    let(:webserver_payload) do
      { runtimeConfigFields:
          [{ definition:  'webserver1', value: '1.2.3.4' },
           { definition: 'do_you', value: 'see_me' }],
        file: { source: {} }.to_json
      }
    end

    it 'omits webserver runtime config fields' do
      post '/ddtf/tests', webserver_payload.to_json, headers
      build_id = MultiJson.load(last_response.body)['id'].to_s
      post "/ddtf/tests/#{build_id}/retest", headers
      response = MultiJson.load(last_response.body)
      expected_runtime_config = [{ 'definition' => 'do_you', 'value' => 'see_me' }]
      expect(response['runtimeConfigFields']).to eq(expected_runtime_config)
    end

    it 'returns test suite definition' do
      post '/ddtf/tests', post_payload, headers
      build_id = MultiJson.load(last_response.body)['id'].to_s
      get '/ddtf/tests/' + build_id, headers
      response = MultiJson.load(last_response.body)
      expect(response['tsdContent']).to eq build['tsdContent']
    end
  end

  context 'GET /ddtf/tests/:id/part' do
    it 'TODO ..write tests here'
  end

  context 'POST /ddtf/tests' do
    context 'data not parsable' do
      before do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:build_all) { raise 'BOOM!' }
      end

      it 'returns status code 422' do
        post '/ddtf/tests', post_payload, headers
        expect(last_response.status).to eq(422)
        expect(last_response.body).to include('error')
      end
    end

    context 'data not valid' do
      before :each do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { false }
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:errors) { ['BOOM!'] }
      end

      it 'returns status code 400' do
        post '/ddtf/tests', post_payload, headers
        expect(last_response.status).to eq(400)
      end

      it 'returns array of reasons' do
        post '/ddtf/tests', post_payload, headers
        expect(JSON.parse(last_response.body)).to be_an_instance_of(Array)
      end
    end

    context 'name not specified in headers' do
      before :each do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
      end

      it 'returns status code 422' do
        post '/ddtf/tests', post_payload, {}
        expect(last_response.status).to eq(422)
      end
    end

    context 'build id not retrieved' do
      before do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
        allow(FinalAPI::Endpoint::DDTF::DdtfHelpers).to receive(:get_new_build_params) { {} }
        allow(FinalAPI::Endpoint::DDTF::DdtfHelpers).to receive(:create_build)

        allow(FinalAPI.config.ddtf).to receive(:email_domain) { 'mail.com' }
      end

      it 'returns status code 422' do
        post '/ddtf/tests', post_payload, headers
        expect(last_response.status).to eq(422)
      end

      it 'returns detailed description' do
        post '/ddtf/tests', post_payload, headers
        expect(JSON.parse(last_response.body)).to include('error' => 'Could not create new build')
      end
    end

    context 'request succeeds' do
      let(:build) { Factory(:build) }

      before do
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:valid?) { true }
        allow_any_instance_of(TsdUtils::EnqueueData).to receive(:clusters) { ['cluster'] }
        allow(FinalAPI::Endpoint::DDTF::DdtfHelpers).to receive(:get_new_build_params) { {} }
        allow(FinalAPI::Endpoint::DDTF::DdtfHelpers).to receive(:create_build) { build }

        allow(FinalAPI.config).to receive(:allowed_origin) { '*' }

        allow(TsdUtils::EnqueueData).to receive(:prepare_xml)
      end

      it 'returns status code 200' do
        post '/ddtf/tests', post_payload, headers
        expect(last_response.status).to eq(200)
      end

      it 'returns expected data' do
        post '/ddtf/tests', post_payload, headers
        expect(JSON.parse(last_response.body)).to include(
          'id', 'name', 'build', 'result', 'results', 'enqueued')
      end

      it 'adds build id' do
        expect_any_instance_of(Travis::Amqp::Publisher).to receive(:publish)
          .with(hash_including(:enqueue_data => a_string_matching("<BuildId>#{build.id}</BuildId>")))

        post '/ddtf/tests', post_payload, headers
      end
    end
  end

  describe 'PUT /ddtf/tests/:id/stop' do
    let(:build) { Factory(:build, state: 'created') }

    it 'set state in DB' do
      put "/ddtf/tests/#{build.id}/stop"
      expect(last_response.status).to eq(200)
      build.reload
      expect(build.state).to eq 'canceled'
    end
  end
end
