module SecApi
  class Mapping
    def initialize(client)
      @_client = client
    end

    def ticker(ticker)
      @_client.connection.get("/mapping/ticker/#{ticker}").tap do |response|
        raise "Error: #{response.status}" unless response.success?
        return response.body
      end
    end

    def cik(cik)
      @_client.connection.get("/mapping/cik/#{cik}").tap do |response|
        raise "Error: #{response.status}" unless response.success?
        return response.body
      end
    end

    def cusip(cusip)
      @_client.connection.get("/mapping/cusip/#{cusip}").tap do |response|
        raise "Error: #{response.status}" unless response.success?
        return response.body
      end
    end

    def name(name)
      @_client.connection.get("/mapping/name/#{name}").tap do |response|
        raise "Error: #{response.status}" unless response.success?
        return response.body
      end
    end
  end
end