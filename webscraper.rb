require 'watir'
require 'selenium-webdriver'
require 'optparse'
require 'set'
# require 'byebug'

module SiteHelper
  # Chrome options for Docker environment
  CHROME_OPTIONS = Selenium::WebDriver::Chrome::Options.new.tap do |options|
    options.add_argument('--headless')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--disable-gpu')
    options.add_argument('--disable-software-rasterizer')
    options.add_argument('--remote-debugging-port=9222')
    options.add_argument('--disable-site-isolation-trials')
    options.add_argument('--disable-web-security')
    options.add_argument('--disable-features=IsolateOrigins,site-per-process')
    options.add_argument('--no-default-browser-check')
    options.add_argument('--no-first-run')
    options.add_argument('--incognito')
    options.add_argument('--ignore-certificate-errors')
    options.add_argument('--ignore-ssl-errors')
    options.add_argument('--disable-extensions')
    options.add_argument('--disable-browser-side-navigation')
    options.add_argument('--dns-prefetch-disable')
    options.add_argument('--window-size=1200,1600')
    options.add_argument('--proxy-bypass-list=*')
  end.freeze

  def site
    @site ||= Site.new(Watir::Browser.new(:chrome, options: CHROME_OPTIONS))
  end
end

module Navigation
  def goto(url)
    browser.goto(url)

    # Only accept cookies on Interamt website
    if url.include?('interamt.de')
      accept_cookies
    end

    self
  end

  private

  def accept_cookies
    cookie_accept_selected = browser.button(class: 'ia-e-button ia-js-cookie-accept__selected')
    if cookie_accept_selected.exists?
      puts "Found ia-e-button ia-js-cookie-accept__selected button, clicking it"
      begin
        cookie_accept_selected.click
        puts "Successfully clicked the cookie accept button"
        sleep 2
        return true
      rescue => e
        puts "Error clicking cookie accept button: #{e.message}"
        take_screenshot("cookie_button_click_error.png")
      end
    end

    if browser.element(id: 'cookie-modal-headline').exists?
      puts "Cookie modal detected with headline"
      cookie_buttons = browser.buttons

      accept_button = cookie_buttons.find do |btn|
        btn_text = btn.text.downcase
        btn_text.include?('accept') || btn_text.include?('ok') ||
        btn_text.include?('next') || btn_text.include?('agree') ||
        btn_text.include?('akzeptieren') || btn_text.include?('zustimmen')
      end

      if accept_button && accept_button.exists?
        puts "Clicking cookie acceptance button with text: #{accept_button.text}"
        accept_button.click
        sleep 2
        return true
      else
        puts "Cookie modal found but couldn't find the acceptance button"
        take_screenshot("cookie_modal_no_button.png")
      end
    end
  end
end

class BrowserContainer
  attr_reader :browser

  include Navigation

  def initialize(browser)
    @browser = browser
  end

  def close
    @browser.close
  end
end

class Site < BrowserContainer
  def service_bund_page
    @service_bund_page ||= ServiceBund.new(browser)
  end

  def interamt_page
    @interamt_page ||= Interamt.new(browser)
  end
end

class Page < BrowserContainer
  include Navigation

  def initialize(browser, url)
    super(browser)
    goto(url)
  end
end

class Interamt < Page
  URL = "https://interamt.de/koop/app/trefferliste".freeze # All job listings

  def initialize(browser)
      super(browser, URL)
  end

  # Main method to run the extraction process
  def extract_job_descriptions(max_jobs = 200)
      puts "Starting direct job description extraction for up to #{max_jobs} jobs"
      
      job_data = []
      current_job_count = 0
      
      # Create directory for saving job details
      Dir.mkdir('job_details') unless Dir.exist?('job_details')
      
      # Continue until we've processed enough jobs or can't find more
      while current_job_count < max_jobs
      puts "Processing batch of jobs (#{current_job_count}/#{max_jobs} completed so far)"
      
      # Wait for the table to load
      begin
          browser.wait_until(timeout: 30) { browser.tbody.exists? }
      rescue Watir::Wait::TimeoutError
          puts "Table not found after waiting 30 seconds - no more results or page error"
          take_screenshot("table_timeout_#{Time.now.to_i}.png")
          break
      end
      
      # Get all visible rows
      rows = browser.tbody.trs
      
      if rows.empty?
          puts "No job rows found on current page"
          break
      end
      
      puts "Found #{rows.length} job rows in current view"
      
      # Process each visible row
      rows.each_with_index do |row, index|
          # Break if we've reached the maximum
          if current_job_count >= max_jobs
          puts "Reached target of #{max_jobs} jobs"
          break
          end
          
          puts "Processing job row #{index + 1}/#{rows.length} (total processed: #{current_job_count + 1})"
          
          # Extract basic job info from row
          job_info = extract_job_info_from_row(row)
          
          if job_info
          # Click on the row to go to job details
          begin
              # Use JavaScript click as it's more reliable with table rows
              browser.execute_script("arguments[0].click();", row)
              puts "Clicked job row for: #{job_info[:stellenbezeichnung]}"
              
              # Wait for page to load
              browser.wait_until(timeout: 30) { browser.ready_state == 'complete' }
              sleep 2 # Give JavaScript a moment to fully render
              
              # Extract job description
              description_content = extract_job_description_content
              
              if description_content && !description_content.empty?
              # Save the content
              filename = save_job_description(job_info[:id], description_content)
              job_info[:description_file] = filename
              job_info[:description_saved] = true
              puts "✓ Successfully extracted description for job #{job_info[:id]}"
              else
              puts "✗ Failed to extract description for job #{job_info[:id]}"
              job_info[:description_saved] = false
              take_screenshot("failed_description_#{job_info[:id]}_#{Time.now.to_i}.png")
              end
              
              # Add to our collection
              job_data << job_info
              current_job_count += 1
              
              # Go back to results page
              browser.goto URL
              
              # Wait for table to load again
              browser.wait_until(timeout: 30) { browser.tbody.exists? }
              sleep 1 # Brief pause to ensure page is ready
              
          rescue => e
              puts "✗ Error processing job row: #{e.message}"
              take_screenshot("error_processing_row_#{Time.now.to_i}.png")
              
              # Go back to results page to continue with next job
              browser.goto URL
              browser.wait_until(timeout: 30) { browser.tbody.exists? }
          end
          end
      end
      
      # If we haven't reached our target job count, try to load more results
      if current_job_count < max_jobs
          if !click_load_more_button
          puts "No more results available - reached end of job listings"
          break
          end
      else
          break
      end
      end
      
      # Final report
      puts "Job description extraction complete!"
      puts "Total jobs processed: #{job_data.length}"
      puts "Successfully processed jobs: #{job_data.count { |j| j[:description_saved] }}"
      puts "Failed jobs: #{job_data.count { |j| !j[:description_saved] }}"
      
      return job_data
  end

  # Extract job info from a table row
  def extract_job_info_from_row(row)
      begin
      stellenangebot_id = nil
      behoerde = nil
      stellenbezeichnung = nil
      
      row.tds.each do |td|
          data_field = td.attribute('data-field')
          case data_field
          when 'StellenangebotId'
          stellenangebot_id = td.span.text.strip
          when 'Behoerde'
          behoerde = td.text.strip
          when 'Stellenbezeichnung'
          stellenbezeichnung = td.text.strip
          end
      end
      
      # Only return if we have at least an ID
      if stellenangebot_id && !stellenangebot_id.empty?
          return {
          id: clean_text(stellenangebot_id),
          behoerde: clean_text(behoerde || "Unknown"),
          stellenbezeichnung: clean_text(stellenbezeichnung || "Unknown"),
          timestamp: Time.now.to_i
          }
      else
          puts "Could not extract job ID from row, skipping"
          return nil
      end
      rescue => e
      puts "Error extracting job info from row: #{e.message}"
      return nil
      end
  end

  # Method to extract job description content
  def extract_job_description_content
      content = nil
      
      # Try multiple potential selectors for job description content
      # First approach: Look for the rich text content div
      if browser.div(class: 'ia-e-richtext ia-h-space--top-l').exists?
      content = browser.div(class: 'ia-e-richtext ia-h-space--top-l').html
      puts "Found description using richtext class selector"
      # Second approach: Look for the primary tab content
      elsif browser.div(id: 'ia-tab-primary').exists?
      content = browser.div(id: 'ia-tab-primary').html
      puts "Found description using primary tab selector"
      # Third approach: Look for description block with any class containing 'description'
      elsif browser.div(class: /description|stellenbeschreibung|jobdetail/i).exists?
      content = browser.div(class: /description|stellenbeschreibung|jobdetail/i).html
      puts "Found description using fallback class selector"
      # Fourth approach: Try to get the main content area
      elsif browser.div(role: 'main').exists?
      content = browser.div(role: 'main').html
      puts "Found description using main content role"
      end
      
      # If all else fails, get the body content
      if content.nil? || content.strip.empty?
      puts "No specific content container found, capturing full body content"
      content = browser.body.html
      end
      
      return content
  end

  # Method to save job description to file
  def save_job_description(job_id, content)
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      filename = File.join('job_details', "job_#{job_id}_#{timestamp}.html")
      
      # Save HTML content
      File.write(filename, content)
      puts "Saved job description to #{filename}"
      
      # Take screenshot for verification
      screenshot_filename = File.join('job_details', "job_#{job_id}_screenshot_#{timestamp}.png")
      take_screenshot(screenshot_filename)
      
      return filename
  end

  def click_load_more_button
      puts "Looking for 'mehr laden' button..."
      load_more_button = nil

      # Try finding by ID first
      if browser.button(id: 'id1').exists?
      load_more_button = browser.button(id: 'id1')
      # Try finding by class
      elsif browser.button(class: /ia-m-searchresultsbtn-load/).exists?
      load_more_button = browser.button(class: /ia-m-searchresultsbtn-load/)
      # Try finding by the span label
      elsif browser.button { |btn| btn.span(class: 'ia-e-buttonlabel', text: 'mehr laden').exists? }.exists?
      load_more_button = browser.button { |btn| btn.span(class: 'ia-e-buttonlabel', text: 'mehr laden').exists? }
      end

      # If we can't find the button or it's not visible, we might have reached the end
      if load_more_button.nil? || !load_more_button.exists? || !load_more_button.visible?
      puts "No 'mehr laden' button found. All results may be loaded."
      take_screenshot("no_more_button_found_#{Time.now.to_i}.png")
      return false
      end

      # Scroll to the button to ensure it's in view
      browser.execute_script("arguments[0].scrollIntoView(true);", load_more_button)
      sleep 1

      # Click the button
      begin
      load_more_button.click
      puts "Clicked 'mehr laden' button"

      wait_time = 5
      puts "Waiting #{wait_time} seconds for new results to load..."
      sleep wait_time

      # Wait for the table to update - look for the table to be present again
      browser.wait_until(timeout: 30) { browser.tbody.exists? }

      return true
      rescue => e
      puts "Error clicking 'mehr laden' button: #{e.message}"
      take_screenshot("error_clicking_load_more_#{Time.now.to_i}.png")
      return false
      end
  end

  def clean_text(text)
      return nil if text.nil?
      text.strip.gsub(/\s+/, ' ')
  end

  def take_screenshot(filename, y=2600)
      browser.window.resize_to(1200, y)

      browser.screenshot.save(filename)
  rescue => e
      puts "Failed to take screenshot #{filename}: #{e.message}"
  end
  end

  class ScraperCLI
  include SiteHelper

  def initialize
      @options = {
      portal: nil,
      keyword: "",
      max_jobs: 50,         # default number of jobs to extract
      }
  end

  def parse_options
      OptionParser.new do |opts|
      opts.banner = <<~BANNER
          Job Description Extractor

          Basic Usage:
          ruby webscraper.rb --portal interamt [options]

          Examples:
          # Extract job descriptions
          ruby webscraper.rb --portal interamt --keyword "Informatiker" --max-jobs 100

          Available Options:
      BANNER

      opts.on("--portal PORTAL", ["interamt"],
              "Required. Only interamt.de portal is supported") do |portal|
          @options[:portal] = portal
      end

      opts.on("--keyword KEYWORD",
              "Search keyword for job listings",
              "Default: ''") do |keyword|
          @options[:keyword] = keyword
      end

      opts.on("--max-jobs N", Integer,
              "Maximum number of job descriptions to extract",
              "Default: 50") do |n|
          @options[:max_jobs] = n
      end

      end.parse!

      validate_options
  end

  def validate_options
      unless @options[:portal] && @options[:portal] == "interamt"
      puts "Error: Only --portal interamt is supported"
      puts "For help, use: ruby webscraper.rb --help"
      exit 1
      end
  end

  def run
      parse_options

      begin
      interamt_page = site.interamt_page

      # Navigate to URL and apply keyword filter if provided
      if @options[:keyword] && !@options[:keyword].empty?
          puts "Searching for keyword: #{@options[:keyword]}"
          # Add search keyword functionality here
          # This would depend on how the interamt search works
      end

      # Start extracting job descriptions 
      puts "Starting job description extraction for up to #{@options[:max_jobs]} jobs"
      job_data = interamt_page.extract_job_descriptions(@options[:max_jobs])
      
      # Save results summary to JSON
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      summary_file = "job_extraction_summary_#{timestamp}.json"
      File.write(summary_file, JSON.generate({
          total_jobs: job_data.length,
          successful: job_data.count { |j| j[:description_saved] },
          failed: job_data.count { |j| !j[:description_saved] },
          extraction_date: timestamp,
          jobs: job_data
      }))
      
      puts "Saved results summary to #{summary_file}"
      
      ensure
      site.close
      end
  end
  end

  # Execute the script
  if __FILE__ == $0
  ScraperCLI.new.run
  end
