# frozen_string_literal: true

require_relative "base"

module RubyLlm
  module Providers
    class OpenAi < Base
      def call(messages:, temperature:, max_tokens:, tools: nil, &block)
        uri = URI("#{@base_url}/chat/completions")
        
        payload = {
          model: @model,
          messages: messages,
          temperature: temperature,
          max_tokens: max_tokens
        }

        payload[:tools] = tools if tools && !tools.empty?

        if block_given?
          payload[:stream] = true
          stream_response(uri, payload, &block)
        else
          response = post_json(uri, payload, auth_header: "Bearer #{@api_key}")
          normalize_response(response)
        end
      end

      def get_embedding(text)
        uri = URI("#{@base_url}/embeddings")
        payload = {
          input: text,
          model: @model
        }

        response = post_json(uri, payload, auth_header: "Bearer #{@api_key}")
        response.dig(:data, 0, :embedding) || []
      end

      private

      def normalize_response(data)
        return empty_response if data.empty?

        message = data.dig(:choices, 0, :message) || {}
        content = message[:content] || ''
        tool_calls = message[:tool_calls]
        
        usage = data[:usage]
        finish_reason = data.dig(:choices, 0, :finish_reason)

        RubyLlm::Response.new(
          content: content,
          model: @model,
          format_name: @format_name,
          usage: usage ? {
            prompt_tokens: usage[:prompt_tokens],
            completion_tokens: usage[:completion_tokens],
            total_tokens: usage[:total_tokens]
          } : nil,
          finish_reason: finish_reason,
          tool_calls: tool_calls,
          raw_response: data
        )
      end

      def stream_response(uri, payload, &block)
        content_buffer = +""
        post_json(uri, payload, auth_header: "Bearer #{@api_key}") do |chunk|
          chunk.split("\n\n").each do |line|
            next unless line.start_with?("data: ")
            data_str = line.sub("data: ", "").strip
            break if data_str == "[DONE]"
            
            begin
              json = JSON.parse(data_str, symbolize_names: true)
              delta = json.dig(:choices, 0, :delta, :content)
              if delta && !delta.empty?
                content_buffer << delta
                yield delta, content_buffer
              end
            rescue JSON::ParserError
              # Ignore partial chunks
            end
          end
        end

        RubyLlm::Response.new(
          content: content_buffer,
          model: @model,
          format_name: @format_name,
          finish_reason: 'stop', # Assuming normal completion for stream right now
          raw_response: { stream_result: content_buffer }
        )
      end

      def empty_response
        RubyLlm::Response.new(content: '', model: @model, format_name: @format_name)
      end
    end
  end
end
