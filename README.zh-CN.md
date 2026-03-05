# RubyLlm

[![Ruby](https://img.shields.io/badge/Language-Ruby-red.svg)](https://www.ruby-lang.org/)

**一个干净、轻量级、为 LLM 核心提供者（OpenAI, Anthropic, Gemini）设计的统一接口适配器。**

`RubyLlm` 将主流 AI 提供商底层的差异抽象成了同一套直白可用的 API。它开箱即用地支持普通文本生成、数据流（Streaming）和工具函数调用。

---

## 📖 Documentation / 文档

- [English Version](README.en.md)
- [中文版本](README.zh-CN.md)

---

### 支持的 API 格式 (Formats)
- `openai` (GPT-3.5, GPT-4, DeepSeek 等等)
- `anthropic` (Claude 3, Claude 3.5 等等)
- `gemini` (Gemini Pro, Flash 等等)

### 1. 安装

在项目的 Gemfile 中添加：

```ruby
gem 'ruby_llm', path: 'path/to/ruby_llm'
```

然后执行：
```bash
bundle install
```

### 2. 基础初始化与文本生成

初始化服务时，你需要指定 API `format` 并且**显式传入**你的 `api_key`。

```ruby
require 'ruby_llm'

openai = RubyLlm::LLMService.new(
  format: 'openai',
  model: 'gpt-4o',
  api_key: ENV['OPENAI_API_KEY']
)

# 基础调用
response = openai.call("你好！请用一句话解释量子计算。")
puts response.format_name # => "openai"
puts response.content     # => "量子计算是一种..."

# 查看 Token 消耗和停止原因
puts response.usage          # => {:prompt_tokens=>15, :completion_tokens=>24...}
puts response.finish_reason  # => "stop"
```

### 3. 连接自定义端点 (以用 OpenAI 格式调 DeepSeek 为例)

你可以通过自定义 `base_url` 来轻松连接那些兼容主流 API 格式的第三方大模型：

```ruby
deepseek = RubyLlm::LLMService.new(
  format: 'openai',               # 底层使用标准的 OpenAI API 结构请求
  model: 'deepseek-chat', 
  api_key: ENV['DEEPSEEK_API_KEY'],
  base_url: 'https://api.deepseek.com/v1',
  ssl_verify_none: false          # 在部分企业代理环境下如果遇到证书问题可设为 true
)

response = deepseek.call("请用 Ruby 写一个快速排序。")
```

### 4. 通过 YAML 配置文件初始化

为了避免在代码里硬编码大模型配置，你可以提供一个统一的 yaml profile 进行加载解耦。

创建一个 `llm.yml`:
```yaml
openai:
  format: "openai"
  model: "gpt-4o"
  api_key: "ENV['OPENAI_API_KEY']"

deepseek:
  format: "openai"
  base_url: "https://api.deepseek.com/v1"
  model: "deepseek-chat"
  api_key: "${DEEPSEEK_API_KEY}"
  ssl_verify_none: true
```

只需在初始化时传入使用的配置节点名即可（它会按照 `llm.yml` -> `config/llm.yml` 的顺序自动嗅探文件）：

```ruby
deepseek = RubyLlm::LLMService.new(
  profile_name: 'deepseek'
)

# 如果想指定特定位置的 yml
# deepseek = RubyLlm::LLMService.new(profile_name: 'deepseek', profile_path: 'path/to/llm.yml')
```

### 5. 流式响应 (Streaming Yield Block)

所有的 API 格式都原生支持通过 Block yield 的方式实现 HTTP 分块流式读取。方法向后传递 `(delta, full_buffer)`。

```ruby
anthropic = RubyLlm::LLMService.new(
  format: 'anthropic',
  model: 'claude-3-5-sonnet-20240620',
  api_key: ENV['ANTHROPIC_API_KEY']
)

anthropic.call("给我写一个 3 句话的 Ruby 简介。") do |chunk, buffer|
  print chunk
  # 'chunk' 是这一次 tick 接收到的增量文本
  # 'buffer' 是截止目前接收到的所有完整文本
end
```

### 6. 系统提示词与多轮对话支持

```ruby
history = [
  { role: 'user', content: '你好，我是 Bob。' },
  { role: 'assistant', content: '你好 Bob！我能帮你什么？' }
]

response = anthropic.call_with_system(
  system_prompt: '你是一个乐于助人的助手，说话总是很简短。',
  user_prompt: '我的名字是什么？',
  conversation_history: history,
  temperature: 0.2
)

puts response.content # => "你的名字是 Bob。"
```

### 7. 工具/函数调用 (Function Calling)

你可以按照目标格式的规范定义 `tools` 数组并将其传入。

```ruby
tools = [{
  type: "function",
  function: {
    name: "get_current_weather",
    description: "获取给定地点的当前天气",
    parameters: {
      type: "object",
      properties: {
        location: { type: "string", description: "城市和州，例如 San Francisco, CA" }
      },
      required: ["location"]
    }
  }
}]

response = openai.call("波士顿今天天气怎么样？", tools: tools)

if response.has_tool_calls?
  call_request = response.tool_calls.first
  puts call_request[:function][:name]      # => "get_current_weather"
  puts call_request[:function][:arguments] # => "{\"location\":\"Boston, MA\"}"
end
```

### 8. 提取语义向量 (Embeddings)

```ruby
gemini = RubyLlm::LLMService.new(
  format: 'gemini', 
  model: 'text-embedding-004',
  api_key: ENV['GEMINI_API_KEY']
)

vector = gemini.get_embedding("我们来测试一下这个 embedding 字符串。")
puts vector.size # => e.g., 768
```
