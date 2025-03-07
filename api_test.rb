# frozen_string_literal: true

require 'openai'

# API configuration
access_token = ENV['API_KEY']
api_base = 'https://chat-ai.academiccloud.de/v1'
model = 'llama-3.1-nemotron-70b-instruct'

job_file_path = 'job_001.txt'
job_content = File.read(job_file_path)

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
      { role: 'user', content: "Extrahiere die geforderten Kompetenzen aus der Stellenanzeige: #{job_content}" }
    ]
  }
)

# Print full response as JSON
puts chat_completion

File.write('response_1.txt', chat_completion.to_json)
