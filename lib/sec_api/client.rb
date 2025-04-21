module SecApi
  class Client
    def initialize(config = Config.new)
      @_config = config
    end

    def config
      @_config
    end

    def connection
      @_connection ||= begin
        Faraday.new(url: @_config.base_url) do |conn|
          conn.request :json
          conn.response :json, content_type: /\bjson$/, parser_options: { symbolize_names: true }
          conn.headers["Authorization"] = @_config.api_key
          conn.adapter Faraday.default_adapter
        end
      end
    end

    def query
      @_query ||= Query.new(self)
    end

    def extractor
      @_extractor ||= Extractor.new(self)
    end

    def mapping
      @_mapping ||= Mapping.new(self)
    end
  end
end