# frozen_string_literal: true

module RubyLlm
  class Response
    attr_reader :content, :model, :provider, :usage, :finish_reason, :raw_response, :tool_calls

    def initialize(content:, model:, provider:, usage: nil, finish_reason: nil, tool_calls: nil, raw_response: nil)
      @content = content
      @model = model
      @provider = provider
      @usage = usage # { prompt_tokens:, completion_tokens:, total_tokens: }
      @finish_reason = finish_reason
      @tool_calls = tool_calls || []
      @raw_response = raw_response
    end

    def has_tool_calls?
      @tool_calls && !@tool_calls.empty?
    end

    def to_h
      {
        content: @content,
        model: @model,
        provider: @provider,
        usage: @usage,
        finish_reason: @finish_reason,
        tool_calls: @tool_calls
      }
    end
  end
end
