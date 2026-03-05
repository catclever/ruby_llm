# frozen_string_literal: true

require 'dotenv'
Dotenv.load(File.expand_path('../../.env', __dir__))

require_relative '../lib/ruby_llm'

puts "Testing OpenAI Format..."
openai = RubyLlm::LLMService.new(
  format: 'openai',
  model: 'gpt-4o',
  api_key: ENV['OPENAI_API_KEY'] || 'fake-key'
)

response = openai.call("Respond with 'Hello from OpenAI!'")
puts "OpenAI Format Response (Format: #{response.format_name}): #{response.content}\n\n"

puts "Testing Anthropic Profile Format..."
anthropic = RubyLlm::LLMService.new(
  profile_name: 'anthropic',
  profile_path: 'spec/fixtures/llm.yml'
)

print "Anthropic Streaming Response: "
anthropic.call("Give me a 3-sentence summary of Ruby on Rails.") do |chunk, _buffer|
  print chunk
end
puts "\n\n"

puts "Finished Testing."
