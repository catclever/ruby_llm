# frozen_string_literal: true

require_relative "base"

module RubyLlm
  module Providers
    class Anthropic < Base
      def call(messages:, temperature:, max_tokens:, tools: nil, &block)
        uri = URI("#{@base_url}/messages")

        system_content = nil
        anthropic_messages = []

        messages.each do |msg|
          if msg[:role] == 'system'
            system_content = msg[:content]
          else
            anthropic_messages << { role: msg[:role], content: msg[:content] }
          end
        end

        payload = {
          model: @model,
          messages: anthropic_messages,
          max_tokens: max_tokens,
          temperature: temperature
        }
        payload[:system] = system_content if system_content
        payload[:tools] = tools if tools && !tools.empty?

        headers = {
          'x-api-key' => @api_key,
          'anthropic-version' => '2023-06-01'
        }

        if block_given?
          payload[:stream] = true
          stream_response(uri, payload, headers, &block)
        else
          response = post_json(uri, payload, custom_headers: headers)
          normalize_response(response)
        end
      end

      def get_embedding(text)
        @logger.warn('Anthropic does not provide embedding API natively via this adapter')
        []
      end

      private

      def normalize_response(data)
        return empty_response if data.empty?

        content_blocks = data[:content] || []
        
        # Anthropic separates text and tool_use blocks
        text_content = content_blocks
                        .select { |block| block[:type] == 'text' }
                        .map { |block| block[:text] }
                        .join

        # Extract tool calls if any
        tool_blocks = content_blocks.select { |block| block[:type] == 'tool_use' }
        tool_calls = nil
        unless tool_blocks.empty?
          tool_calls = tool_blocks.map do |block|
            {
              id: block[:id],
              type: "function",
              function: {
                name: block[:name],
                arguments: block[:input].to_json
              }
            }
          end
        end

        usage = data[:usage]
        stop_reason = data[:stop_reason]

        RubyLlm::Response.new(
          content: text_content,
          model: @model,
          provider: @provider_name,
          usage: usage ? {
            prompt_tokens: usage[:input_tokens],
            completion_tokens: usage[:output_tokens],
            total_tokens: usage[:input_tokens].to_i + usage[:output_tokens].to_i
          } : nil,
          finish_reason: stop_reason,
          tool_calls: tool_calls,
          raw_response: data
        )
      end

      def stream_response(uri, payload, headers, &block)
        content_buffer = +""
        
        post_json(uri, payload, custom_headers: headers) do |chunk|
          chunk.split("\n\n").each do |line|
            next unless line.start_with?("data: ")
            data_str = line.sub("data: ", "").strip
            
            begin
              json = JSON.parse(data_str, symbolize_names: true)
              # Anthropic stream events have different types
              if json[:type] == 'content_block_delta' && json.dig(:delta, :type) == 'text_delta'
                delta = json.dig(:delta, :text)
                if delta && !delta.empty?
                  content_buffer << delta
                  yield delta, content_buffer
                end
              end
            rescue JSON::ParserError
              # ignore
            end
          end
        end

        RubyLlm::Response.new(content: content_buffer, model: @model, provider: @provider_name, finish_reason: 'stop')
      end

      def empty_response
        RubyLlm::Response.new(content: '', model: @model, provider: @provider_name)
      end
    end
  end
end
