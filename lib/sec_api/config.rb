require "anyway_config"

module SecApi
  class Config < Anyway::Config
    attr_config :api_key
    attr_config base_url: "https://api.sec-api.io"
  end
end