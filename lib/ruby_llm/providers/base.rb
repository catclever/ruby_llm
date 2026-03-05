# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'logger'

module RubyLlm
  module Providers
    class Base
      attr_reader :model, :api_key, :base_url, :timeout, :logger

      def initialize(model:, api_key:, base_url:, timeout:, logger: nil)
        @model = model
        @api_key = api_key
        @base_url = base_url
        @timeout = timeout
        @logger = logger || Logger.new($stdout)
      end

      # @abstract
      # @param messages [Array<Hash>] 
      # @param temperature [Float]
      # @param max_tokens [Integer]
      # @param tools [Array<Hash>] Optional Tools definition
      # @yield [String] Stream chunk if block given
      def call(messages:, temperature:, max_tokens:, tools: nil, &block)
        raise NotImplementedError
      end

      # @abstract
      def get_embedding(text)
        raise NotImplementedError
      end

      protected

      def post_json(uri, payload, auth_header: nil, custom_headers: nil, skip_auth: false, &block)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')
        http.read_timeout = @timeout
        http.open_timeout = @timeout

        request = Net::HTTP::Post.new(uri.path + (uri.query ? "?#{uri.query}" : ''))
        request['Content-Type'] = 'application/json'

        unless skip_auth
          if custom_headers
            custom_headers.each { |k, v| request[k] = v }
          elsif auth_header
            request['Authorization'] = auth_header
          end
        end

        request.body = payload.to_json

        @logger.debug("POST #{uri} with payload: #{payload.to_json}")

        buffer = ""
        if block_given?
          # Streaming implementation
          http.request(request) do |response|
            if response.code.to_i >= 400
              @logger.error("HTTP error #{response.code}: #{response.body}")
              return {}
            end
            response.read_body do |chunk|
              yield chunk
            end
          end
          return {} # For streaming, the raw parsing is handled by the provider subclasses
        else
          response = http.request(request)
          if response.code.to_i >= 400
            @logger.error("HTTP error #{response.code}: #{response.body}")
            return {}
          end
          JSON.parse(response.body, symbolize_names: true)
        end
      rescue StandardError => e
        @logger.error("HTTP request failed: #{e.message}")
        {}
      end
    end
  end
end
