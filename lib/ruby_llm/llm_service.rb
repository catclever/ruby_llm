# frozen_string_literal: true

require 'net/http'
require 'uri'
require 'json'
require 'logger'

##
# LLM 服务层 - 支持多种 LLM 提供商
# 支持的提供商：
# - OpenAI (openai)
# - Anthropic Claude (anthropic)
# - Google Gemini (gemini)
#
# 统一的响应格式，屏蔽不同提供商的差异
class LLMService
  # 统一的响应结构
  class Response
    attr_reader :content, :model, :provider, :usage, :finish_reason, :raw_response

    def initialize(content:, model:, provider:, usage: nil, finish_reason: nil, raw_response: nil)
      @content = content
      @model = model
      @provider = provider
      @usage = usage # { prompt_tokens:, completion_tokens:, total_tokens: }
      @finish_reason = finish_reason
      @raw_response = raw_response
    end

    def to_h
      {
        content: @content,
        model: @model,
        provider: @provider,
        usage: @usage,
        finish_reason: @finish_reason
      }
    end
  end

  SUPPORTED_PROVIDERS = %w[openai anthropic gemini].freeze
  DEFAULT_TIMEOUT = 30

  attr_reader :provider, :model, :api_key, :base_url, :default_temperature, :default_max_tokens

  ##
  # 初始化 LLM 服务
  #
  # @param provider [String] 提供商类型: 'openai', 'anthropic', 'gemini'
  # @param model [String] 模型名称
  # @param api_key [String] API 密钥
  # @param base_url [String] API 基础 URL（可选，使用默认值）
  # @param temperature [Float] 默认温度参数
  # @param max_tokens [Integer] 默认最大 token 数
  # @param logger [Logger] 日志记录器
  def initialize(
    provider: 'openai',
    model: 'gpt-4',
    api_key: nil,
    base_url: nil,
    temperature: 0.7,
    max_tokens: 2000,
    logger: nil
  )
    @provider = provider.to_s.downcase
    raise ArgumentError, "Unsupported provider: #{@provider}" unless SUPPORTED_PROVIDERS.include?(@provider)

    @model = model
    @api_key = api_key || ''
    @base_url = (base_url || default_base_url_for_provider).chomp('/')
    @default_temperature = temperature
    @default_max_tokens = max_tokens
    @logger = logger || Logger.new($stdout)
    @timeout = DEFAULT_TIMEOUT

    @logger.info("LLMService initialized: provider=#{@provider} model=#{@model} base_url=#{@base_url}")
  end

  ##
  # 简单调用（单轮对话）
  #
  # @param prompt [String] 用户提示词
  # @param temperature [Float] 温度参数（可选）
  # @param max_tokens [Integer] 最大 token 数（可选）
  # @param model [String] 模型名称（可选，覆盖默认值）
  # @return [Response] 统一的响应对象
  def call(prompt, temperature: nil, max_tokens: nil, model: nil)
    raise ArgumentError, 'Prompt cannot be empty' if prompt.nil? || prompt.empty?

    messages = [{ role: 'user', content: prompt }]
    call_with_messages(
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens,
      model: model
    )
  end

  ##
  # 带系统提示词的调用
  #
  # @param system_prompt [String] 系统提示词
  # @param user_prompt [String] 用户提示词（与 conversation_history 二选一）
  # @param conversation_history [Array<Hash>] 多轮对话历史（可选）
  # @param temperature [Float] 温度参数（可选）
  # @param max_tokens [Integer] 最大 token 数（可选）
  # @param model [String] 模型名称（可选）
  # @return [Response] 统一的响应对象
  def call_with_system(
    system_prompt:,
    user_prompt: nil,
    conversation_history: nil,
    temperature: nil,
    max_tokens: nil,
    model: nil
  )
    messages = build_messages_with_system(
      system_prompt: system_prompt,
      user_prompt: user_prompt,
      conversation_history: conversation_history
    )

    call_with_messages(
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens,
      model: model
    )
  end

  ##
  # 使用消息列表调用 LLM
  #
  # @param messages [Array<Hash>] 消息列表
  # @param temperature [Float] 温度参数（可选）
  # @param max_tokens [Integer] 最大 token 数（可选）
  # @param model [String] 模型名称（可选）
  # @return [Response] 统一的响应对象
  def call_with_messages(messages:, temperature: nil, max_tokens: nil, model: nil)
    temp = temperature || @default_temperature
    tokens = max_tokens || @default_max_tokens
    target_model = model || @model

    case @provider
    when 'openai'
      call_openai(messages, temp, tokens, target_model)
    when 'anthropic'
      call_anthropic(messages, temp, tokens, target_model)
    when 'gemini'
      call_gemini(messages, temp, tokens, target_model)
    else
      raise "Unknown provider: #{@provider}"
    end
  rescue StandardError => e
    @logger.error("LLM call failed: #{e.message}")
    @logger.error(e.backtrace.join("\n"))
    Response.new(content: '', model: target_model, provider: @provider)
  end

  ##
  # 获取文本的 Embedding 向量
  #
  # @param text [String] 输入文本
  # @param model [String] Embedding 模型名称（可选）
  # @param instruction [String] 指令前缀（可选）
  # @return [Array<Float>] 向量数组
  def get_embedding(text, model: nil, instruction: nil)
    input_text = instruction ? "#{instruction}#{text}" : text
    target_model = model || @model || 'text-embedding-3-small'

    case @provider
    when 'openai'
      get_openai_embedding(input_text, target_model)
    when 'anthropic'
      # Anthropic 不提供 embedding API，需要使用第三方
      @logger.warn('Anthropic does not provide embedding API')
      []
    when 'gemini'
      get_gemini_embedding(input_text, target_model)
    else
      []
    end
  rescue StandardError => e
    @logger.error("Get embedding failed: #{e.message}")
    []
  end

  private

  ##
  # 获取提供商的默认 base URL
  def default_base_url_for_provider
    case @provider
    when 'openai'
      'https://api.openai.com/v1'
    when 'anthropic'
      'https://api.anthropic.com/v1'
    when 'gemini'
      'https://generativelanguage.googleapis.com/v1beta'
    else
      'https://api.openai.com/v1'
    end
  end

  ##
  # 构建带系统提示词的消息列表
  def build_messages_with_system(system_prompt:, user_prompt: nil, conversation_history: nil)
    messages = []

    # Anthropic 使用不同的系统消息处理方式，这里先统一构建
    # 在具体调用时再做转换
    messages << { role: 'system', content: system_prompt }

    if conversation_history && !conversation_history.empty?
      messages.concat(conversation_history)
    elsif user_prompt
      messages << { role: 'user', content: user_prompt }
    else
      raise ArgumentError, 'Either user_prompt or conversation_history must be provided'
    end

    messages
  end

  ##
  # OpenAI 格式调用
  def call_openai(messages, temperature, max_tokens, model)
    uri = URI("#{@base_url}/chat/completions")
    payload = {
      model: model,
      messages: messages,
      temperature: temperature,
      max_tokens: max_tokens
    }

    response = post_json(uri, payload, auth_header: "Bearer #{@api_key}")
    normalize_openai_response(response, model)
  end

  ##
  # Anthropic Claude 格式调用
  def call_anthropic(messages, temperature, max_tokens, model)
    uri = URI("#{@base_url}/messages")

    # Anthropic 的 system 消息需要单独提取
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
      model: model,
      messages: anthropic_messages,
      max_tokens: max_tokens,
      temperature: temperature
    }
    payload[:system] = system_content if system_content

    headers = {
      'x-api-key' => @api_key,
      'anthropic-version' => '2023-06-01'
    }

    response = post_json(uri, payload, custom_headers: headers)
    normalize_anthropic_response(response, model)
  end

  ##
  # Google Gemini 格式调用
  def call_gemini(messages, temperature, max_tokens, model)
    # Gemini API endpoint: /models/{model}:generateContent
    uri = URI("#{@base_url}/models/#{model}:generateContent?key=#{@api_key}")

    # Gemini 的 system 指令需要单独设置
    system_instruction = nil
    gemini_contents = []

    messages.each do |msg|
      if msg[:role] == 'system'
        system_instruction = { parts: [{ text: msg[:content] }] }
      else
        # Gemini 使用 'user' 和 'model' 角色
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

    response = post_json(uri, payload, skip_auth: true)
    normalize_gemini_response(response, model)
  end

  ##
  # 统一的 HTTP POST JSON 请求
  def post_json(uri, payload, auth_header: nil, custom_headers: nil, skip_auth: false)
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

    response = http.request(request)

    if response.code.to_i >= 400
      @logger.error("HTTP error #{response.code}: #{response.body}")
      return {}
    end

    JSON.parse(response.body, symbolize_names: true)
  rescue StandardError => e
    @logger.error("HTTP request failed: #{e.message}")
    {}
  end

  ##
  # 规范化 OpenAI 响应
  def normalize_openai_response(data, model)
    return Response.new(content: '', model: model, provider: 'openai') if data.empty?

    content = data.dig(:choices, 0, :message, :content) || ''
    usage = data[:usage]
    finish_reason = data.dig(:choices, 0, :finish_reason)

    Response.new(
      content: content,
      model: model,
      provider: 'openai',
      usage: usage ? {
        prompt_tokens: usage[:prompt_tokens],
        completion_tokens: usage[:completion_tokens],
        total_tokens: usage[:total_tokens]
      } : nil,
      finish_reason: finish_reason,
      raw_response: data
    )
  end

  ##
  # 规范化 Anthropic 响应
  def normalize_anthropic_response(data, model)
    return Response.new(content: '', model: model, provider: 'anthropic') if data.empty?

    # Anthropic 响应格式：
    # {
    #   content: [{ type: 'text', text: '...' }],
    #   stop_reason: 'end_turn',
    #   usage: { input_tokens:, output_tokens: }
    # }
    content_blocks = data[:content] || []
    text_content = content_blocks
                    .select { |block| block[:type] == 'text' }
                    .map { |block| block[:text] }
                    .join

    usage = data[:usage]
    stop_reason = data[:stop_reason]

    Response.new(
      content: text_content,
      model: model,
      provider: 'anthropic',
      usage: usage ? {
        prompt_tokens: usage[:input_tokens],
        completion_tokens: usage[:output_tokens],
        total_tokens: usage[:input_tokens].to_i + usage[:output_tokens].to_i
      } : nil,
      finish_reason: stop_reason,
      raw_response: data
    )
  end

  ##
  # 规范化 Gemini 响应
  def normalize_gemini_response(data, model)
    return Response.new(content: '', model: model, provider: 'gemini') if data.empty?

    # Gemini 响应格式：
    # {
    #   candidates: [
    #     {
    #       content: { parts: [{ text: '...' }] },
    #       finishReason: 'STOP'
    #     }
    #   ],
    #   usageMetadata: { promptTokenCount:, candidatesTokenCount:, totalTokenCount: }
    # }
    candidates = data[:candidates] || []
    first_candidate = candidates.first || {}

    parts = first_candidate.dig(:content, :parts) || []
    text_content = parts.map { |part| part[:text] }.join

    usage_metadata = data[:usageMetadata]
    finish_reason = first_candidate[:finishReason]

    Response.new(
      content: text_content,
      model: model,
      provider: 'gemini',
      usage: usage_metadata ? {
        prompt_tokens: usage_metadata[:promptTokenCount],
        completion_tokens: usage_metadata[:candidatesTokenCount],
        total_tokens: usage_metadata[:totalTokenCount]
      } : nil,
      finish_reason: finish_reason,
      raw_response: data
    )
  end

  ##
  # OpenAI Embedding
  def get_openai_embedding(text, model)
    uri = URI("#{@base_url}/embeddings")
    payload = {
      input: text,
      model: model
    }

    response = post_json(uri, payload, auth_header: "Bearer #{@api_key}")
    response.dig(:data, 0, :embedding) || []
  end

  ##
  # Gemini Embedding
  def get_gemini_embedding(text, model)
    # Gemini Embedding endpoint: /models/{model}:embedContent
    uri = URI("#{@base_url}/models/#{model}:embedContent?key=#{@api_key}")
    payload = {
      content: {
        parts: [{ text: text }]
      }
    }

    response = post_json(uri, payload, skip_auth: true)
    response.dig(:embedding, :values) || []
  end
end
