module SecApi
  class Xbrl
    def initialize(client)
      @_client = client
    end

    def to_json(filing, options = {})
      request_params = {}
      request_params[:"xbrl-url"] = filing.xbrl_url unless filing.xbrl_url.empty?
      request_params[:"accession-no"] = filing.accession_number unless filing.accession_number.empty?
      request_params.merge!(options) unless options.empty?

      @_client.connection.get("/xbrl-to-json", request_params).tap do |response|
        raise "Error: #{response.status}" unless response.success?
        return response.body
      end
    end
  end
end
