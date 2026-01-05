# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Specific Error Classes" do
  describe "Transient Errors" do
    describe SecApi::RateLimitError do
      it "inherits from TransientError" do
        expect(described_class).to be < SecApi::TransientError
      end

      it "can be instantiated with a message" do
        error = described_class.new("Rate limit exceeded")
        expect(error.message).to eq("Rate limit exceeded")
      end

      it "can be rescued as TransientError" do
        expect {
          begin
            raise described_class, "Test"
          rescue SecApi::TransientError
            # Successfully caught
          end
        }.not_to raise_error
      end
    end

    describe SecApi::ServerError do
      it "inherits from TransientError" do
        expect(described_class).to be < SecApi::TransientError
      end

      it "can be instantiated with a message" do
        error = described_class.new("Server error")
        expect(error.message).to eq("Server error")
      end

      it "can be rescued as TransientError" do
        expect {
          begin
            raise described_class, "Test"
          rescue SecApi::TransientError
            # Successfully caught
          end
        }.not_to raise_error
      end
    end

    describe SecApi::NetworkError do
      it "inherits from TransientError" do
        expect(described_class).to be < SecApi::TransientError
      end

      it "can be instantiated with a message" do
        error = described_class.new("Network timeout")
        expect(error.message).to eq("Network timeout")
      end

      it "can be rescued as TransientError" do
        expect {
          begin
            raise described_class, "Test"
          rescue SecApi::TransientError
            # Successfully caught
          end
        }.not_to raise_error
      end
    end
  end

  describe "Permanent Errors" do
    describe SecApi::AuthenticationError do
      it "inherits from PermanentError" do
        expect(described_class).to be < SecApi::PermanentError
      end

      it "can be instantiated with a message" do
        error = described_class.new("Authentication failed")
        expect(error.message).to eq("Authentication failed")
      end

      it "can be rescued as PermanentError" do
        expect {
          begin
            raise described_class, "Test"
          rescue SecApi::PermanentError
            # Successfully caught
          end
        }.not_to raise_error
      end
    end

    describe SecApi::NotFoundError do
      it "inherits from PermanentError" do
        expect(described_class).to be < SecApi::PermanentError
      end

      it "can be instantiated with a message" do
        error = described_class.new("Resource not found")
        expect(error.message).to eq("Resource not found")
      end

      it "can be rescued as PermanentError" do
        expect {
          begin
            raise described_class, "Test"
          rescue SecApi::PermanentError
            # Successfully caught
          end
        }.not_to raise_error
      end
    end

    describe SecApi::ValidationError do
      it "inherits from PermanentError" do
        expect(described_class).to be < SecApi::PermanentError
      end

      it "can be instantiated with a message" do
        error = described_class.new("Validation failed")
        expect(error.message).to eq("Validation failed")
      end

      it "can be rescued as PermanentError" do
        expect {
          begin
            raise described_class, "Test"
          rescue SecApi::PermanentError
            # Successfully caught
          end
        }.not_to raise_error
      end
    end
  end

  describe "Type-based rescue patterns" do
    it "allows rescuing all transient errors together" do
      errors_caught = []

      [SecApi::RateLimitError, SecApi::ServerError, SecApi::NetworkError].each do |error_class|
        begin
          raise error_class, "Test"
        rescue SecApi::TransientError => e
          errors_caught << e.class
        end
      end

      expect(errors_caught).to contain_exactly(
        SecApi::RateLimitError,
        SecApi::ServerError,
        SecApi::NetworkError
      )
    end

    it "allows rescuing all permanent errors together" do
      errors_caught = []

      [SecApi::AuthenticationError, SecApi::NotFoundError, SecApi::ValidationError].each do |error_class|
        begin
          raise error_class, "Test"
        rescue SecApi::PermanentError => e
          errors_caught << e.class
        end
      end

      expect(errors_caught).to contain_exactly(
        SecApi::AuthenticationError,
        SecApi::NotFoundError,
        SecApi::ValidationError
      )
    end

    it "distinguishes between transient and permanent errors" do
      transient_caught = false
      permanent_caught = false

      begin
        raise SecApi::RateLimitError, "Test"
      rescue SecApi::TransientError
        transient_caught = true
      rescue SecApi::PermanentError
        permanent_caught = true
      end

      expect(transient_caught).to be true
      expect(permanent_caught).to be false

      transient_caught = false
      permanent_caught = false

      begin
        raise SecApi::AuthenticationError, "Test"
      rescue SecApi::TransientError
        transient_caught = true
      rescue SecApi::PermanentError
        permanent_caught = true
      end

      expect(transient_caught).to be false
      expect(permanent_caught).to be true
    end
  end
end
