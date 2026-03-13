# RubyLLM

[![Ruby](https://img.shields.io/badge/Language-Ruby-red.svg)](https://www.ruby-lang.org/)

**A clean, lightweight, and unified interface for LLM providers (OpenAI, Anthropic, Gemini).**

`RubyLlm` abstract the differences between major AI providers into a single straightforward API, supporting normal completion, streaming, and tool/function calling logic out of the box.

---

## 📖 Documentation / 文档

- [English Version](README.en.md)
- [中文版本](README.zh-CN.md)

---
## English Version

### Supported Formats
- `openai` (GPT-3.5, GPT-4, DeepSeek, etc.)
- `anthropic` (Claude 3, Claude 3.5, etc.)
- `gemini` (Gemini Pro, Flash, etc.)

### 1. Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby_llm', path: 'path/to/ruby_llm'
```

And then execute:
```bash
bundle install
```

### 2. Basic Initialization & Text Generation

Initialize the service by specifying the API `format` and explicitly providing your `api_key`.

```ruby
require 'ruby_llm'

openai = RubyLlm::LLMService.new(
  format: 'openai',
  model: 'gpt-4o',
  api_key: ENV['OPENAI_API_KEY']
)

# Standard Call
response = openai.call("Hello! Please explain Quantum Computing in one sentence.")
puts response.format_name # => "openai"
puts response.content     # => "Quantum computing is..."

# Check Token Usage
puts response.usage          # => {:prompt_tokens=>15, :completion_tokens=>24...}
puts response.finish_reason  # => "stop"
```

### 3. Custom Endpoints (e.g. DeepSeek using OpenAI Format)

You can easily interact with API providers that mimic standard formats by supplying a custom `base_url`:

```ruby
deepseek = RubyLlm::LLMService.new(
  format: 'openai',               # It uses standard OpenAI API structure
  model: 'deepseek-chat', 
  api_key: ENV['DEEPSEEK_API_KEY'],
  base_url: 'https://api.deepseek.com/v1',
  ssl_verify_none: false          # Set true for enterprise proxy configurations
)

response = deepseek.call("Please write a quick sort in Ruby.")
```

### 4. Initialization via YAML Profile

To cleanly manage different providers without hardcoding configurations into your application, you can use a YAML profile file. 

Create a `llm.yml` file:
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

Then load the specific profile during service initialization:

```ruby
# The `format` explicitly resolves to the profile key (e.g. `openai`) 
# when no `name` or `profile_name` is provided inside the hash.
deepseek = RubyLlm::LLMService.new(
  profile: 'path/to/llm.yml',
  format: 'deepseek'
)

# Equivalent explicit dictionary form:
# deepseek = RubyLlm::LLMService.new(profile: { path: 'path/to/llm.yml', name: 'deepseek' })
```

### 5. Streaming Responses (Yield Block)

All formats support streaming HTTP chunks using a block yield. The method yields `(delta, full_buffer)`.

```ruby
anthropic = RubyLlm::LLMService.new(
  format: 'anthropic',
  model: 'claude-3-5-sonnet-20240620',
  api_key: ENV['ANTHROPIC_API_KEY']
)

anthropic.call("Give me a 3-sentence summary of Ruby.") do |chunk, buffer|
  print chunk
  # 'chunk' is the partial text received in this tick.
  # 'buffer' contains all the text received so far.
end
```

### 6. Using System Prompts and Conversation History

```ruby
history = [
  { role: 'user', content: 'Hi, I am Bob.' },
  { role: 'assistant', content: 'Hello Bob! How can I help?' }
]

response = anthropic.call_with_system(
  system_prompt: 'You are a helpful assistant who always speaks briefly.',
  user_prompt: 'What is my name?',
  conversation_history: history,
  temperature: 0.2
)

puts response.content # => "Your name is Bob."
```

### 7. Function / Tool Calling

You can pass an array of tools defined in the format standard to your LLM provider.

```ruby
tools = [{
  type: "function",
  function: {
    name: "get_current_weather",
    description: "Get the current weather in a given location",
    parameters: {
      type: "object",
      properties: {
        location: { type: "string", description: "The city and state, e.g. San Francisco, CA" }
      },
      required: ["location"]
    }
  }
}]

response = openai.call("What is the weather like in Boston?", tools: tools)

if response.has_tool_calls?
  call_request = response.tool_calls.first
  puts call_request[:function][:name]      # => "get_current_weather"
  puts call_request[:function][:arguments] # => "{\"location\":\"Boston, MA\"}"
end
```

### 8. Embeddings extraction

```ruby
gemini = RubyLlm::LLMService.new(
  format: 'gemini', 
  model: 'text-embedding-004',
  api_key: ENV['GEMINI_API_KEY']
)

vector = gemini.get_embedding("Let's test this embedding string.")
puts vector.size # => e.g., 768
```


