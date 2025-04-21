module SecApi
  class Query
    def initialize(client)
      @_client = client
    end

    def search(query, options = {})
      @_client.connection.post("/", { query: query }.merge(options)).tap do |response|
        raise "Error: #{response.status}" unless response.success?
        return Collections::Filings.new(response.body)
      end
    end

    def fulltext(query, options = {})
      @_client.connection.post("/full-text-search", { query: query }.merge(options)).tap do |response|
        raise "Error: #{response.status}" unless response.success?
        return FulltextResults.new(response.body)
      end
    end
  end
end