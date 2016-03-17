
module FinalAPI
  module Cors
    def self.registered(app)
      app.before do
        response['Access-Control-Allow-Origin'] = FinalAPI.config.allowed_origin
      end

      app.options "*" do
        response.headers["Allow"] = "HEAD,GET,PUT,DELETE,OPTIONS"
        response.headers["Access-Control-Allow-Headers"] = "X-Requested-With, X-HTTP-Method-Override, Content-Type, Cache-Control, Accept, name, AuthenticationToken"
        halt 200
      end

      app.set :protection, :origin_whitelist => FinalAPI.config.allowed_origin
    end
  end
end
