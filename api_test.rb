require 'openai'

# API configuration
access_token = ENV['ACADEMICCLOUD_API_KEY']
api_base = 'https://chat-ai.academiccloud.de/v1'
model = 'meta-llama-3.1-8b-instruct'

# Start OpenAI client
client = OpenAI::Client.new(
  access_token: access_token,
  uri_base: api_base,
  log_errors: true
)

# Get response
chat_completion = client.chat(
  parameters: {
    model: model,
    messages: [
      { role: 'system', content: 'You are a helpful assistant' },
      { role: 'user', content: 'How tall is the Eiffel tower?' }
    ]
  }
)

# Print full response as JSON
puts chat_completion
