module SecApi
  class Extractor
    def initialize(client)
      @_client = client
    end

    def extract(filing, options = {})
      url = filing.url unless filing.is_a?(String)
      url ||= filing
      @_client.connection.post("/extractor", { url: url }.merge(options)).tap do |response|
        raise "Error: #{response.status}" unless response.success?
        return response.body
      end
    end
  end
end