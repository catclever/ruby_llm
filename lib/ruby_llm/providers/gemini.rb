# frozen_string_literal: true

require_relative "base"

module RubyLLM
  module Providers
    class Gemini < Base
      def call(messages:, temperature:, max_tokens:, tools: nil, &block)
        # Gemini API stream endpoint: /models/{model}:streamGenerateContent?alt=sse
        endpoint = block_given? ? "streamGenerateContent?alt=sse&key=#{@api_key}" : "generateContent?key=#{@api_key}"
        uri = URI("#{@base_url}/models/#{@model}:#{endpoint}")

        system_instruction = nil
        gemini_contents = []

        messages.each do |msg|
          if msg[:role] == 'system'
            system_instruction = { parts: [{ text: msg[:content] }] }
          else
            role = msg[:role] == 'assistant' ? 'model' : 'user'
            gemini_contents << {
              role: role,
              parts: [{ text: msg[:content] }]
            }
          end
        end

        payload = {
          contents: gemini_contents,
          generationConfig: {
            temperature: temperature,
            maxOutputTokens: max_tokens
          }
        }
        payload[:systemInstruction] = system_instruction if system_instruction
        # Note: Gemini tool calling implementation varies slightly. Using standard format here.
        payload[:tools] = [{ functionDeclarations: tools }] if tools && !tools.empty?

        if block_given?
          stream_response(uri, payload, &block)
        else
          response = post_json(uri, payload, skip_auth: true)
          normalize_response(response)
        end
      end

      def get_embedding(text)
        uri = URI("#{@base_url}/models/#{@model}:embedContent?key=#{@api_key}")
        payload = {
          content: { parts: [{ text: text }] }
        }

        response = post_json(uri, payload, skip_auth: true)
        response.dig(:embedding, :values) || []
      end

      private

      def normalize_response(data)
        return empty_response if data.empty?

        candidates = data[:candidates] || []
        first_candidate = candidates.first || {}

        parts = first_candidate.dig(:content, :parts) || []
        text_content = parts.map { |part| part[:text] }.join

        usage_metadata = data[:usageMetadata]
        finish_reason = first_candidate[:finishReason]

        RubyLLM::Response.new(
          content: text_content,
          model: @model,
          format_name: @format_name,
          usage: usage_metadata ? {
            prompt_tokens: usage_metadata[:promptTokenCount],
            completion_tokens: usage_metadata[:candidatesTokenCount],
            total_tokens: usage_metadata[:totalTokenCount]
          } : nil,
          finish_reason: finish_reason,
          raw_response: data
        )
      end

      def stream_response(uri, payload, &block)
        content_buffer = +""
        
        post_json(uri, payload, skip_auth: true) do |chunk|
          chunk.split("\n\n").each do |line|
            next unless line.start_with?("data: ")
            data_str = line.sub("data: ", "").strip
            
            begin
              json = JSON.parse(data_str, symbolize_names: true)
              candidates = json[:candidates] || []
              first = candidates.first || {}
              
              parts = first.dig(:content, :parts) || []
              text = parts.map { |part| part[:text] }.join
              
              if text && !text.empty?
                content_buffer << text
                yield text, content_buffer
              end
            rescue JSON::ParserError
              # Ignore
            end
          end
        end

        RubyLLM::Response.new(content: content_buffer, model: @model, format_name: @format_name, finish_reason: 'stop')
      end

      def empty_response
        RubyLLM::Response.new(content: '', model: @model, format_name: @format_name)
      end
    end
  end
end
