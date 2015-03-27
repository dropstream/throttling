require 'singleton'
require 'redis'

module Throttling
  module Storage
    class Redis
      include Singleton

      @@options ||= {}
      # Pass Redis options before calling instance for the first time
      def self.options=(options)
        @@options = options
      end

      def initialize
        @redis = ::Redis.new(@@options)
      end

      # Implementation of the storage fetch method, as prescribed by the
      # Throttling module.
      def fetch(key, options = {}, &block)
        value = @redis.get(key)
        if value.nil?
          value = yield.to_i
          @redis.set(key, value)
          @redis.expire(key, options[:expires_in]) if options.has_key?(:expires_in)
        end
        value
      end

      # Implementation of the storage increment method, as prescribed by the
      # Throttling module.
      def increment(key)
        @redis.incr(key)
      end
    end
  end
end
