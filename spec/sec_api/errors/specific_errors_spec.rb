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

      describe "request_id propagation" do
        it "accepts request_id keyword argument" do
          error = described_class.new("Rate limited", request_id: "rate-123")
          expect(error.request_id).to eq("rate-123")
        end

        it "includes request_id in error message" do
          error = described_class.new("Rate limited", request_id: "rate-456")
          expect(error.message).to eq("[rate-456] Rate limited")
        end

        it "passes request_id alongside retry_after and reset_at" do
          reset_time = Time.now + 60
          error = described_class.new(
            "Rate limited",
            retry_after: 30,
            reset_at: reset_time,
            request_id: "rate-789"
          )
          expect(error.request_id).to eq("rate-789")
          expect(error.retry_after).to eq(30)
          expect(error.reset_at).to eq(reset_time)
          expect(error.message).to include("[rate-789]")
        end
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

      describe "request_id propagation" do
        it "accepts request_id keyword argument" do
          error = described_class.new("Server error", request_id: "srv-123")
          expect(error.request_id).to eq("srv-123")
        end

        it "includes request_id in error message" do
          error = described_class.new("Server error", request_id: "srv-456")
          expect(error.message).to eq("[srv-456] Server error")
        end
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

      describe "request_id propagation" do
        it "accepts request_id keyword argument" do
          error = described_class.new("Network timeout", request_id: "net-123")
          expect(error.request_id).to eq("net-123")
        end

        it "includes request_id in error message" do
          error = described_class.new("Network timeout", request_id: "net-456")
          expect(error.message).to eq("[net-456] Network timeout")
        end
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

      describe "request_id propagation" do
        it "accepts request_id keyword argument" do
          error = described_class.new("Auth failed", request_id: "auth-123")
          expect(error.request_id).to eq("auth-123")
        end

        it "includes request_id in error message" do
          error = described_class.new("Auth failed", request_id: "auth-456")
          expect(error.message).to eq("[auth-456] Auth failed")
        end
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

      describe "request_id propagation" do
        it "accepts request_id keyword argument" do
          error = described_class.new("Not found", request_id: "nf-123")
          expect(error.request_id).to eq("nf-123")
        end

        it "includes request_id in error message" do
          error = described_class.new("Not found", request_id: "nf-456")
          expect(error.message).to eq("[nf-456] Not found")
        end
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

      describe "request_id propagation" do
        it "accepts request_id keyword argument" do
          error = described_class.new("Invalid input", request_id: "val-123")
          expect(error.request_id).to eq("val-123")
        end

        it "includes request_id in error message" do
          error = described_class.new("Invalid input", request_id: "val-456")
          expect(error.message).to eq("[val-456] Invalid input")
        end
      end
    end

    describe SecApi::PaginationError do
      it "inherits from PermanentError" do
        expect(described_class).to be < SecApi::PermanentError
      end

      it "can be instantiated with a message" do
        error = described_class.new("No more pages available")
        expect(error.message).to eq("No more pages available")
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

      describe "request_id propagation" do
        it "accepts request_id keyword argument" do
          error = described_class.new("No more pages", request_id: "page-123")
          expect(error.request_id).to eq("page-123")
        end

        it "includes request_id in error message" do
          error = described_class.new("No more pages", request_id: "page-456")
          expect(error.message).to eq("[page-456] No more pages")
        end
      end
    end
  end

  describe "Type-based rescue patterns" do
    it "allows rescuing all transient errors together" do
      errors_caught = []

      [SecApi::RateLimitError, SecApi::ServerError, SecApi::NetworkError].each do |error_class|
        raise error_class, "Test"
      rescue SecApi::TransientError => e
        errors_caught << e.class
      end

      expect(errors_caught).to contain_exactly(
        SecApi::RateLimitError,
        SecApi::ServerError,
        SecApi::NetworkError
      )
    end

    it "allows rescuing all permanent errors together" do
      errors_caught = []

      [SecApi::AuthenticationError, SecApi::NotFoundError, SecApi::ValidationError, SecApi::PaginationError].each do |error_class|
        raise error_class, "Test"
      rescue SecApi::PermanentError => e
        errors_caught << e.class
      end

      expect(errors_caught).to contain_exactly(
        SecApi::AuthenticationError,
        SecApi::NotFoundError,
        SecApi::ValidationError,
        SecApi::PaginationError
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
