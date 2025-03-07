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

# Start OpenAI client
client = OpenAI::Client.new(
  access_token: access_token,
  uri_base: api_base,
  log_errors: true
)

# Helper method to match a competency to DigComp framework
def match_to_digcomp(competency_text, digcomp_framework)
  matches = []
  
  # Convert competency text to lowercase for case-insensitive matching
  competency_text_lower = competency_text.downcase
  
  digcomp_framework[:digcomp_competencies].each do |area|
    area_name = area[:area]
    
    area[:competencies].each do |competency|
      competency_id = competency[:id]
      competency_desc = competency[:description]
      
      # Check if any keyword from this competency is in the competency text
      matching_keywords = competency[:keywords].select do |keyword|
        competency_text_lower.include?(keyword.downcase)
      end
      
      if matching_keywords.any?
        matches << {
          area: area_name,
          competency_id: competency_id,
          description: competency_desc,
          matching_keywords: matching_keywords
        }
      end
    end
  end
  
  matches
end

# Extract competencies from the API response content
def extract_competencies(content)
  competencies = []
  
  # Split by lines and look for the competency sections
  lines = content.split("\n")
  current_category = nil
  current_competency = nil
  
  lines.each do |line|
    # Skip empty lines
    next if line.strip.empty?
    
    # Detect main categories (bold text with **, may have numbers)
    if line.match?(/\*\*[\w\s\/\(\)]+:\*\*/)
      current_category = line.gsub(/\*\*|\*\*/, '').strip
      next
    end
    
    # Detect competency items (usually start with * or + or numbers or tabs)
    if line.match?(/^\s*[\*\+\d\t-]\s+/)
      clean_line = line.gsub(/^\s*[\*\+\d\t-]\s+/, '').strip
      
      # If it ends with a colon, it's a sub-category
      if clean_line.end_with?(':')
        current_competency = clean_line.chomp(':').strip
      else
        # It's an actual competency
        competencies << {
          category: current_category,
          subcategory: current_competency,
          description: clean_line
        }
      end
    end
  end
  
  competencies
end

# Process each file in the response directory
Dir.glob('response/*.json').each do |response_file_path|
  puts "Processing response file: #{response_file_path}"
  
  # Read response content
  response_json = JSON.parse(File.read(response_file_path))
  
  # Extract the content from the AI response
  ai_content = response_json['choices'][0]['message']['content']
  
  # Extract competencies
  extracted_competencies = extract_competencies(ai_content)
  
  # Match each competency with DigComp framework
  matched_competencies = []
  
  extracted_competencies.each do |comp|
    full_description = "#{comp[:category]} - #{comp[:subcategory]} - #{comp[:description]}"
    matches = match_to_digcomp(full_description, digcomp)
    
    matched_competencies << {
      job_competency: comp,
      digcomp_matches: matches
    } if matches.any?
  end
  
  # Create the final result
  result = {
    original_response: response_json,
    extracted_competencies: extracted_competencies,
    digcomp_matches: matched_competencies
  }
  
  # Save to a new file
  output_file_path = response_file_path.sub('.json', '_digcomp.json')
  File.write(output_file_path, JSON.pretty_generate(result))
  
  puts "DigComp matching saved to: #{output_file_path}"
end

puts "All files processed successfully."