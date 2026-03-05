# frozen_string_literal: true

require 'dotenv'
Dotenv.load(File.expand_path('../../.env', __dir__))

require_relative '../lib/ruby_llm'

# 1. Explicit Initialization (Providing API Key Directly)
puts "============================="
puts "1. Explicit Initialization"
puts "============================="
begin
  openai = RubyLlm::LLMService.new(
    format: 'openai',
    model: 'gpt-4o',
    api_key: ENV['OPENAI_API_KEY'] || 'fake-key'
  )

  response = openai.call("Respond with 'Hello from OpenAI!'")
  puts "OpenAI Format Response: #{response.content}\n\n"
rescue => e
  puts "Failed to call OpenAI Explicitly: #{e.message}\n\n"
end

# 2. YAML Profile Initialization
puts "============================="
puts "2. YAML Profile Initialization"
puts "============================="
begin
  anthropic = RubyLlm::LLMService.new(
    profile_name: 'anthropic',
    profile_path: File.expand_path('../../spec/fixtures/llm.yml', __FILE__)
  )

  print "Anthropic Streaming Response: "
  anthropic.call("Give me a 3-sentence summary of Ruby on Rails.") do |chunk, _buffer|
    print chunk
  end
  puts "\n\n"
rescue => e
  puts "Failed to call Anthropic via Profile: #{e.message}\n\n"
end
