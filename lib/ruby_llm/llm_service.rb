# frozen_string_literal: true

require 'logger'
require_relative 'response'
require_relative 'profile'
require_relative 'providers/base'
require_relative 'providers/openai'
require_relative 'providers/anthropic'
require_relative 'providers/gemini'

module RubyLLM
  ##
  # LLM Service Facade
  # Supported formats: 'openai', 'anthropic', 'gemini'
  class LLMService
    SUPPORTED_FORMATS = %w[openai anthropic gemini].freeze
    DEFAULT_TIMEOUT = 30

    attr_reader :format_name, :model, :default_temperature, :default_max_tokens
    attr_reader :adapter

    ##
    # Initialize LLM Service
    def initialize(
      api_key: nil,
      format: nil,
      model: nil,
      base_url: nil,
      temperature: nil,
      max_tokens: 2000,
      timeout: nil,
      logger: nil,
      ssl_verify_none: nil,
      profile_name: nil,
      profile_path: nil
    )
      if profile_name
        prof = RubyLLM::Profile.load(profile_name, file_path: profile_path)
        
        format ||= prof.format_name
        model ||= prof.model
        api_key ||= prof.api_key
        base_url ||= prof.base_url
        timeout ||= prof.timeout
        max_tokens = prof.max_tokens if max_tokens == 2000 && prof.max_tokens
        ssl_verify_none = prof.ssl_verify_none if ssl_verify_none.nil?
      end

      # Set defaults if not provided by arguments or profile
      format ||= 'openai'
      model ||= 'gpt-4o'
      ssl_verify_none = false if ssl_verify_none.nil?

      @format_name = format.to_s.downcase
      raise ArgumentError, "Unsupported format: #{@format_name}" unless SUPPORTED_FORMATS.include?(@format_name)

      @model = model
      @default_temperature = temperature
      @default_max_tokens = max_tokens
      @logger = logger || Logger.new($stdout)
      
      raise ArgumentError, "api_key is required" if api_key.nil? || api_key.empty?
      
      base_url ||= default_base_url_for(@format_name)
      
      adapter_class = case @format_name
                      when 'openai' then Providers::OpenAi
                      when 'anthropic' then Providers::Anthropic
                      when 'gemini' then Providers::Gemini
                      end

      @adapter = adapter_class.new(
        model: @model,
        api_key: api_key,
        base_url: base_url.chomp('/'),
        timeout: timeout || DEFAULT_TIMEOUT,
        logger: @logger,
        ssl_verify_none: ssl_verify_none,
        format_name: @format_name
      )

      @logger.info("RubyLLM initialized: format=#{@format_name} model=#{@model}")
    end

    ##
    # Simple call
    def call(prompt, temperature: nil, max_tokens: nil, tools: nil, &block)
      raise ArgumentError, 'Prompt cannot be empty' if prompt.nil? || prompt.empty?

      messages = [{ role: 'user', content: prompt }]
      call_with_messages(
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        tools: tools,
        &block
      )
    end

    ##
    # Call with system prompt
    def call_with_system(
      system_prompt:,
      user_prompt: nil,
      conversation_history: nil,
      temperature: nil,
      max_tokens: nil,
      tools: nil,
      &block
    )
      messages = []
      messages << { role: 'system', content: system_prompt }

      if conversation_history && !conversation_history.empty?
        messages.concat(conversation_history)
      elsif user_prompt
        messages << { role: 'user', content: user_prompt }
      else
        raise ArgumentError, 'Either user_prompt or conversation_history must be provided'
      end

      call_with_messages(
        messages: messages,
        temperature: temperature,
        max_tokens: max_tokens,
        tools: tools,
        &block
      )
    end

    ##
    # Call with raw messages array
    def call_with_messages(messages:, temperature: nil, max_tokens: nil, tools: nil, &block)
      temp = temperature || @default_temperature
      tokens = max_tokens || @default_max_tokens

      # Sanitize messages: API rejects assistant messages with empty/nil content if there are tool_calls
      sanitized_messages = messages.map do |msg|
        # Duplicating to avoid mutating the original array passed by reference
        clean_msg = msg.dup
        role = clean_msg[:role] || clean_msg['role']
        content = clean_msg[:content] || clean_msg['content']
        
        if role.to_s == 'assistant'
          # Strip empty/nil content
          if content.nil? || content.to_s.strip.empty?
            clean_msg.delete(:content)
            clean_msg.delete('content')
          end
          
          # Special case for Moonshot/Kimi 'thinking' models: 
          # It STRICTLY REQUIRES `reasoning_content` to be present for ANY assistant message
          # that contains `tool_calls`, and sometimes even for normal ones if it's part of a reasoning chain.
          # To be absolutely safe with Kimi, we inject `reasoning_content: ""` for ALL assistant messages 
          # if it's missing, because it never hurts and prevents 400s.
          if @model.to_s.include?('kimi') || (@adapter.base_url && @adapter.base_url.to_s.include?('moonshot'))
            clean_msg[:reasoning_content] = "" unless clean_msg.key?(:reasoning_content) || clean_msg.key?('reasoning_content')
          end
        end
        clean_msg
      end

      @adapter.call(
        messages: sanitized_messages,
        temperature: temp, 
        max_tokens: tokens,
        tools: tools,
        &block
      )
    end

    ##
    # Get embedding vector
    def get_embedding(text)
      @adapter.get_embedding(text)
    end

    private

    def default_base_url_for(format_name)
      case format_name.to_s.downcase
      when 'openai' then 'https://api.openai.com/v1'
      when 'anthropic' then 'https://api.anthropic.com/v1'
      when 'gemini' then 'https://generativelanguage.googleapis.com/v1beta'
      end
    end
  end
end
