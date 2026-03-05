# RubyLlm

`RubyLlm` is a lightweight, dependency-free (except for standard network libraries) Ruby adapter for unifying LLM interactions. It abstracts the differences between major AI providers into a single straightforward API, supporting normal completion, streaming, and tool/function calling logic out of the box.

Currently Supported Formats:
- `openai` (GPT-3.5, GPT-4, DeepSeek, etc.)
- `anthropic` (Claude 3, Claude 3.5, etc.)
- `gemini` (Gemini Pro, Flash, etc.)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby_llm', path: 'path/to/ruby_llm'
```

And then execute:
```bash
bundle install
```

## Configuration & Setup

`RubyLlm` requires the respective provider API keys to function. The easiest way to configure these is by setting environment variables. If you are using `dotenv`, place these in your `.env` file:

```env
OPENAI_API_KEY=sk-proj-xxx...
ANTHROPIC_API_KEY=sk-ant-xxx...
GEMINI_API_KEY=AIzaSyBxxx...
```

When initializing the service, if you do not explicitly pass an `api_key`, it will automatically search the environment for `[PROVIDER]_API_KEY`.

## Usage Exampels

### 1. Basic Initialization & Text Generation

```ruby
require 'ruby_llm'

# Initialize the OpenAI service
openai = RubyLlm::LLMService.new(
  format: 'openai',
  model: 'gpt-4o',
  api_key: ENV['OPENAI_API_KEY']
)

# Standard Call
response = openai.call("Hello! Please explain Quantum Computing in one sentence.")
puts response.format_name # => "openai"
puts response.content
# => "Quantum computing is an area of study focused on developing computer technology based on the principles of quantum theory..."

# Check Token Usage
puts response.usage          # => {:prompt_tokens=>15, :completion_tokens=>24...}
puts response.finish_reason  # => "stop"
```

### 2. Custom Endpoints (e.g. DeepSeek using OpenAI Format)

You can easily interact with API providers that mimic standard formats:

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

### 3. Streaming Responses (Yield Block)

All providers (OpenAI, Anthropic, Gemini) support streaming HTTP chunks using a block yield. The method yields `(delta, full_buffer)`.

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

### 3. Using System Prompts and Conversation History

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

puts response.content
# => "Your name is Bob."
```

### 4. Function / Tool Calling

You can pass an array of tools defined in the format standard to your LLM provider. When the LLM decides to substitute the tool, it will populate the `tool_calls` attribute of the response.

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
  puts call_request[:function][:name] 
  # => "get_current_weather"
  
  puts call_request[:function][:arguments] 
  # => "{\"location\":\"Boston, MA\"}"
end
```

### 6. Embeddings extraction

```ruby
gemini = RubyLlm::LLMService.new(
  format: 'gemini', 
  model: 'text-embedding-004',
  api_key: ENV['GEMINI_API_KEY']
)

vector = gemini.get_embedding("Let's test this embedding string.")
puts vector.size # => e.g., 768
```
