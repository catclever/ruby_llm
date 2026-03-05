# frozen_string_literal: true

require 'dotenv'
Dotenv.load(File.expand_path('../../.env', __dir__))

require_relative '../lib/ruby_llm'

puts "Testing OpenAI Format..."
openai = RubyLlm::LLMService.new(
  format: 'openai',
  model: 'gpt-4o',
  api_key: ENV['OPENAI_API_KEY']
)

response = openai.call("Respond with 'Hello from OpenAI!'")
puts "OpenAI Format Response (Provider: #{response.provider}): #{response.content}\n\n"

puts "Testing Anthropic Stream Format..."
anthropic = RubyLlm::LLMService.new(
  format: 'anthropic',
  model: 'claude-3-5-sonnet-20240620',
  api_key: ENV['ANTHROPIC_API_KEY']
)

print "Anthropic Streaming Response: "
anthropic.call("Give me a 3-sentence summary of Ruby on Rails.") do |chunk, _buffer|
  print chunk
end
puts "\n\n"

puts "Finished Testing."
