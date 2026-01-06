# frozen_string_literal: true

module SecApi
  # Mixin module providing deep freeze functionality for immutable value objects.
  #
  # Include this module in Dry::Struct classes that need to ensure nested
  # hashes and arrays are recursively frozen for thread-safety.
  #
  # @example Usage in a Dry::Struct class
  #   class MyObject < Dry::Struct
  #     include SecApi::DeepFreezable
  #
  #     attribute :data, Types::Hash
  #
  #     def initialize(attributes)
  #       super
  #       deep_freeze(data) if data
  #       freeze
  #     end
  #   end
  #
  module DeepFreezable
    private

    # Recursively freezes nested hashes and arrays.
    #
    # @param obj [Object] The object to freeze
    # @return [void]
    def deep_freeze(obj)
      case obj
      when Hash
        obj.each_value { |v| deep_freeze(v) }
        obj.freeze
      when Array
        obj.each { |v| deep_freeze(v) }
        obj.freeze
      else
        obj.freeze if obj.respond_to?(:freeze) && !obj.frozen?
      end
    end
  end
end
