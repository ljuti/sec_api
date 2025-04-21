# frozen_string_literal: true

RSpec.describe SecApi do
  it "has a version number" do
    expect(SecApi.gem_version).not_to be nil
  end
end
