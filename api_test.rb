# frozen_string_literal: true

require 'openai'
require 'fileutils'
require 'json'

# API configuration
access_token = ENV['API_KEY']
api_base = 'https://chat-ai.academiccloud.de/v1'
model = 'llama-3.1-nemotron-70b-instruct'

# Create response directory if it doesn't exist
FileUtils.mkdir_p('response')

# Start OpenAI client
client = OpenAI::Client.new(
  access_token: access_token,
  uri_base: api_base,
  log_errors: true
)

# Process each file in the jobs directory
Dir.glob('jobs/*.txt').each do |job_file_path|
  puts "Processing file: #{job_file_path}"
  
  # Read job content
  job_content = File.read(job_file_path)
  
  # Extract file name without path and extension
  file_name = File.basename(job_file_path, '.txt')
  
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
  
  # Save response to file
  response_file_path = "response/response_#{file_name}.json"
  File.write(response_file_path, chat_completion.to_json)
  
  puts "Response saved to: #{response_file_path}"
  
  # Optional: add a small delay between API calls to avoid rate limiting
  sleep(1) 
end

puts "All files processed successfully."