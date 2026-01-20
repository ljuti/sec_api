require "dry-struct"
require "dry/types"

module SecApi
  # Type definitions for Dry::Struct value objects.
  #
  # Why Dry::Types? (Architecture ADR-8: Value Object Strategy)
  # - Type safety: Catches type mismatches at construction time, not runtime
  # - Automatic coercion: API returns strings for numbers, Dry::Types handles conversion
  # - Immutability: Combined with Dry::Struct, ensures thread-safe response objects
  # - Documentation: Type declarations serve as inline documentation
  #
  # Why not plain Ruby classes? We handle financial data where type errors
  # could lead to incorrect calculations. Explicit types prevent silent failures.
  #
  # This module includes Dry::Types and provides type definitions used across
  # all value objects in the gem. The types ensure type safety and automatic
  # coercion for API response data.
  #
  # @example Using types in a Dry::Struct
  #   class MyStruct < Dry::Struct
  #     attribute :name, SecApi::Types::String
  #     attribute :count, SecApi::Types::Coercible::Integer
  #     attribute :optional_field, SecApi::Types::String.optional
  #   end
  #
  # @see https://dry-rb.org/gems/dry-types/ Dry::Types documentation
  #
  module Types
    include Dry.Types()
  end
end
