# frozen_string_literal: true

require 'openai'
require 'fileutils'

# API configuration
access_token = ENV['API_KEY']
api_base = 'https://chat-ai.academiccloud.de/v1'
model = 'llama-3.1-nemotron-70b-instruct'

# Ensure output directory exists
FileUtils.mkdir_p('job_descriptions')

# Create OpenAI client
client = OpenAI::Client.new(
  access_token: access_token,
  uri_base: api_base,
  log_errors: true
)

# Process each HTML file in job_details folder
Dir.glob('job_details/*.html').each do |html_file_path|
  puts "Processing HTML file: #{html_file_path}"
  
  # Read HTML content
  html_content = File.read(html_file_path)
  
  # Prepare the prompt for the API call
  prompt = <<~PROMPT
    The following is HTML content of a job description. Please extract only the text content, 
    removing all HTML tags and formatting. Preserve the meaningful text structure but remove 
    any HTML markup, scripts, styling, and metadata.
    
    HTML Content:
    #{html_content}
    
    Provide only the clean text content in your response, with no additional commentary.
  PROMPT
  
  # Make API call
  begin
    response = client.chat(
      parameters: {
        model: model,
        messages: [
          { role: 'system', content: 'You are a helpful assistant that extracts clean text content from HTML.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.1
      }
    )
    
    # Get the response content
    result = response.dig('choices', 0, 'message', 'content')
    
    # Generate output filename (using the base name of the HTML file but with .txt extension)
    output_filename = "job_descriptions/#{File.basename(html_file_path, '.html')}.txt"
    
    # Save the extracted text to the output file
    File.write(output_filename, result)
    
    puts "Text content extracted and saved to: #{output_filename}"
  rescue => e
    puts "Error processing #{html_file_path}: #{e.message}"
  end
end

puts "All HTML files processed successfully."