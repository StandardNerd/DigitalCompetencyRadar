# frozen_string_literal: true

require 'openai'
require 'fileutils'
require 'json'
require 'duckdb'

# API configuration
access_token = ENV['API_KEY']
api_base = 'https://chat-ai.academiccloud.de/v1'
model = 'llama-3.1-nemotron-70b-instruct'

# Create output directory if it doesn't exist
FileUtils.mkdir_p('output')

# DigComp framework competencies
digcomp = {
  "digcomp_competencies": [
    {
      "area": "Information and Data Literacy",
      "competencies": [
        {
          "id": "1.1",
          "description": "Browsing, searching, and filtering data, information, and digital content.",
          "keywords": ["search", "filter", "browse", "data", "information"]
        },
        {
          "id": "1.2",
          "description": "Evaluating data, information, and digital content.",
          "keywords": ["evaluate", "assess", "credibility", "relevance"]
        },
        {
          "id": "1.3",
          "description": "Managing data, information, and digital content.",
          "keywords": ["organize", "store", "retrieve", "manage"]
        }
      ]
    },
    {
      "area": "Communication and Collaboration",
      "competencies": [
        {
          "id": "2.1",
          "description": "Interacting through digital technologies.",
          "keywords": ["communicate", "interact", "email", "chat", "messaging"]
        },
        {
          "id": "2.2",
          "description": "Sharing information and content through digital tools.",
          "keywords": ["share", "collaborate", "upload", "download"]
        },
        {
          "id": "2.3",
          "description": "Engaging in citizenship through digital technologies.",
          "keywords": ["citizenship", "participation", "online communities"]
        }
      ]
    },
    {
      "area": "Digital Content Creation",
      "competencies": [
        {
          "id": "3.1",
          "description": "Developing digital content.",
          "keywords": ["create", "edit", "design", "content creation"]
        },
        {
          "id": "3.2",
          "description": "Integrating and re-elaborating digital content.",
          "keywords": ["integrate", "modify", "reuse", "remix"]
        },
        {
          "id": "3.3",
          "description": "Understanding copyright and licenses.",
          "keywords": ["copyright", "licenses", "intellectual property"]
        }
      ]
    },
    {
      "area": "Safety",
      "competencies": [
        {
          "id": "4.1",
          "description": "Protecting devices and digital content.",
          "keywords": ["security", "protect", "devices", "malware"]
        },
        {
          "id": "4.2",
          "description": "Protecting personal data and privacy.",
          "keywords": ["privacy", "data protection", "encryption"]
        },
        {
          "id": "4.3",
          "description": "Protecting health and well-being.",
          "keywords": ["health", "well-being", "ergonomics", "screen time"]
        }
      ]
    },
    {
      "area": "Problem-Solving",
      "competencies": [
        {
          "id": "5.1",
          "description": "Solving technical problems.",
          "keywords": ["troubleshoot", "technical issues", "debug"]
        },
        {
          "id": "5.2",
          "description": "Identifying needs and technological responses.",
          "keywords": ["needs assessment", "technology solutions"]
        },
        {
          "id": "5.3",
          "description": "Innovating and creatively using digital technologies.",
          "keywords": ["innovation", "creativity", "digital tools"]
        }
      ]
    }
  ]
}

# Create OpenAI client
client = OpenAI::Client.new(
  access_token: access_token,
  uri_base: api_base,
  log_errors: true
)

# Ensure the job_descriptions directory exists
unless Dir.exist?('job_descriptions')
  puts "Error: 'job_descriptions' directory does not exist"
  exit 1
end

def clean_json_response(response_text)
  # Remove any markdown code blocks
  cleaned = response_text.gsub(/```(?:json)?\n?/, '')
  # Remove any trailing backticks
  cleaned = cleaned.gsub(/```\s*$/, '')
  # Trim whitespace
  cleaned.strip
end

# Try to initialize DuckDB with proper error handling
begin
  puts "Attempting to initialize DuckDB database..."
  # Create database with no arguments (in-memory by default)
  db = DuckDB::Database.new
  puts "DuckDB database initialized successfully!"
  
  puts "Attempting to connect to database..."
  con = db.connect
  puts "Connected to database successfully!"
  
  puts "Creating table schema..."
  con.execute("CREATE TABLE IF NOT EXISTS job_competencies (
    job_file TEXT, 
    job_title TEXT, 
    extracted_skill TEXT,
    digcomp_area TEXT,
    digcomp_id TEXT,
    confidence INTEGER,
    processed_at TIMESTAMP
  )")
  puts "Table created successfully!"
  
rescue => e
  puts "DuckDB Error: #{e.message}"
  puts "DuckDB Error Class: #{e.class}"
  puts "Backtrace: #{e.backtrace.join("\n")}"
  puts "Will continue with file processing but skip database operations."
  db = nil
  con = nil
end

# Process each job description file
Dir.glob('job_descriptions/*.txt').each do |job_file_path|
  puts "Processing job description: #{job_file_path}"
  
  # Read job description content
  job_description = File.read(job_file_path)
  
  # Prepare the prompt for the API call
  prompt = <<~PROMPT
    You are a digital competency expert who classifies job requirements according to the DigComp framework.
    
    Here is the DigComp 2.1 framework with its competencies:
    #{JSON.pretty_generate(digcomp)}
    
    Below is a job description. Please analyze it and:
    1. Extract all digital skills and competencies mentioned in the job description
    2. For each extracted competency, identify which DigComp competency it corresponds to
    3. Provide a confidence level (1-10) for each match
    4. Format your response as a clean JSON object with the following structure:
    {
      "job_title": "The job title extracted from the description",
      "matches": [
        {
          "extracted_skill": "The exact skill mentioned in the job description",
          "digcomp_area": "The matching DigComp area",
          "digcomp_id": "The competency ID (e.g., 1.1)",
          "digcomp_description": "The official DigComp competency description",
          "confidence": 8,
          "reasoning": "Brief explanation of why this skill matches this competency"
        }
      ]
    }
    
    Job Description:
    #{job_description}
    
    Provide only the JSON object in your response, with no additional text.
  PROMPT
  
  # Make API call
  begin
    response = client.chat(
      parameters: {
        model: model,
        messages: [
          { role: 'system', content: 'You are a helpful assistant that analyzes job descriptions and classifies digital skills according to the DigComp framework.' },
          { role: 'user', content: prompt }
        ],
        temperature: 0.3
      }
    )
    
    # Get the response content
    result = response.dig('choices', 0, 'message', 'content')
    
    # Clean the response before parsing
    cleaned_result = clean_json_response(result)
            
    # Attempt to parse the result as JSON
    begin
      parsed_json = JSON.parse(cleaned_result)
      
      # Create the final result with metadata
      output = {
        source_file: File.basename(job_file_path),
        processed_at: Time.now.strftime('%Y-%m-%dT%H:%M:%S%z'),
        classification_result: parsed_json
      }
      
      # Save to output file
      output_filename = "output/#{File.basename(job_file_path, '.txt')}_digcomp.json"
      File.write(output_filename, JSON.pretty_generate(output))
      
      puts "Classification saved to: #{output_filename}"
      
      # Insert data from each processed job to DuckDB (if database is available)
      if con && parsed_json['matches'] && !parsed_json['matches'].empty?
        begin
          parsed_json['matches'].each do |match|
            con.execute("INSERT INTO job_competencies VALUES (?, ?, ?, ?, ?, ?, ?)",
              [File.basename(job_file_path),
               parsed_json['job_title'],
               match['extracted_skill'],
               match['digcomp_area'],
               match['digcomp_id'],
               match['confidence'],
               Time.now.strftime('%Y-%m-%dT%H:%M:%S')
              ])
          end
          puts "Data inserted into DuckDB for: #{File.basename(job_file_path)}"
        rescue => e
          puts "Failed to insert data into DuckDB: #{e.message}"
        end
      else
        if !con
          puts "Skipping database insert (no active connection)"
        elsif !parsed_json['matches'] || parsed_json['matches'].empty?
          puts "Warning: No matches found for #{File.basename(job_file_path)}"
        end
      end
      
    rescue JSON::ParserError => e
      puts "Error parsing JSON response: #{e.message}"
      
      # Save the raw response for debugging
      error_filename = "output/#{File.basename(job_file_path, '.txt')}_error.txt"
      File.write(error_filename, result)
      
      puts "Raw response saved to: #{error_filename}"
    end
  rescue => e
    puts "API call error: #{e.message}"
  end
end

# Close the database connection if it was opened
if con
  begin
    puts "Closing database connection..."
    con.close
    db.close
    puts "Database connection closed successfully."
  rescue => e
    puts "Error closing database connection: #{e.message}"
  end
end

puts "All job descriptions processed successfully."