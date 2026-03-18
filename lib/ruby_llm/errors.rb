# frozen_string_literal: true

module RubyLLM
  class Error < StandardError; end

  class APIError < Error
    attr_reader :status, :body

    def initialize(message, status: nil, body: nil)
      super(message)
      @status = status
      @body = body
    end
  end
end
