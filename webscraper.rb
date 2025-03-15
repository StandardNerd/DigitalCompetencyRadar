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

  # Main method to run the whole process
  def collect_and_process_jobs(job_count = 200)
    puts "Starting job collection and processing for #{job_count} jobs"
    
    # Step 1: Collect job IDs
    job_data = collect_all_job_ids(job_count)
    puts "Collected #{job_data.length} job IDs"
    
    # Step 2: Process each job to extract descriptions
    process_job_descriptions(job_data)
    
    puts "Job collection and processing complete!"
    return job_data
  end

  def collect_all_job_ids(target_count = 200, checkpoint_interval = 5, resume_checkpoint = nil)
    # Initialize data structures
    collected_jobs = []
    batch_number = 0
    job_id_set = Set.new  # Use a Set for O(1) lookups when checking if ID exists

    # Resume from checkpoint if provided
    if resume_checkpoint && File.exist?(resume_checkpoint)
      begin
        checkpoint_data = JSON.parse(File.read(resume_checkpoint))
        if checkpoint_data['jobs'] && !checkpoint_data['jobs'].empty?
          collected_jobs = checkpoint_data['jobs']
          collected_jobs.each { |job| job_id_set.add(job['id']) }
          batch_number = checkpoint_data['batch_number'] || 0
          puts "Resumed from checkpoint. Already collected #{collected_jobs.length} jobs."
        end
      rescue => e
        puts "Error loading checkpoint: #{e.message}. Starting fresh."
      end
    end

    puts "Starting job ID collection process, target: #{target_count}"
    take_screenshot("initial_page_#{Time.now.to_i}.png")

    # Track how many consecutive batches returned no new jobs
    empty_batch_count = 0
    max_empty_batches = 3  # Give up after this many consecutive empty batches

    while collected_jobs.length < target_count
      # First, wait for the table to load
      begin
        browser.wait_until(timeout: 30) { browser.tbody.exists? }
      rescue Watir::Wait::TimeoutError
        puts "Table not found after waiting 30 seconds - no more results or page error"
        take_screenshot("table_timeout_#{Time.now.to_i}.png")
        break
      end

      # Extract job information from currently visible listings
      new_jobs = extract_visible_job_info
      puts "Found #{new_jobs.length} jobs in current view"

      # Add only unique jobs
      new_jobs_added = 0
      new_jobs.each do |job|
        unless job_id_set.include?(job[:id])
          collected_jobs << job
          job_id_set.add(job[:id])
          new_jobs_added += 1
          
          # Break if we've reached our target
          if collected_jobs.length >= target_count
            puts "Reached target count of #{target_count} jobs"
            break
          end
        end
      end

      puts "Added #{new_jobs_added} new jobs, total now: #{collected_jobs.length} (target: #{target_count})"

      # Check if we got any new jobs
      if new_jobs_added == 0
        empty_batch_count += 1
        puts "No new jobs in this batch. Empty batch count: #{empty_batch_count}/#{max_empty_batches}"

        # If we've had too many empty batches in a row, assume we're not getting any more unique results
        if empty_batch_count >= max_empty_batches
          puts "Reached #{max_empty_batches} consecutive empty batches, ending collection"
          break
        end
      else
        # Reset the empty batch counter if we found new jobs
        empty_batch_count = 0
      end

      # Save checkpoint periodically
      if (batch_number % checkpoint_interval == 0)
        create_checkpoint(collected_jobs, [], "id_collection", batch_number)
      end

      # Stop if we've reached our target
      if collected_jobs.length >= target_count
        break
      end

      # Try to load more results - if no more results are available, break the loop
      if !click_load_more_button
        puts "No more results available - reached end of job listings"
        break
      end

      batch_number += 1
    end

    # Final save
    create_checkpoint(collected_jobs, [], "id_collection", batch_number)
    puts "Completed job ID collection. Total jobs collected: #{collected_jobs.length}"

    collected_jobs
  end

  # Updated method to process job descriptions with better error handling and resumption
  def process_job_descriptions(job_data, batch_size = 10, resume_from_index = 0)
    puts "Starting to process #{job_data.length} job descriptions"
    
    # Count processed and failed jobs
    processed_count = 0
    failed_count = 0
    
    # If resuming, count jobs already processed
    if resume_from_index > 0
      job_data.each_with_index do |job, idx|
        if idx < resume_from_index
          processed_count += 1 if job[:description_saved]
          failed_count += 1 if job.key?(:description_saved) && !job[:description_saved]
        end
      end
      puts "Resuming from index #{resume_from_index}. Already processed: #{processed_count} successful, #{failed_count} failed"
    end
    
    # Create directories for saving job details
    Dir.mkdir('job_details') unless Dir.exist?('job_details')
    
    # Process each job
    job_data[resume_from_index..-1].each_with_index do |job, rel_index|
      actual_index = resume_from_index + rel_index
      puts "Processing job #{actual_index + 1}/#{job_data.length}: ID #{job[:id]}, Title: #{job[:stellenbezeichnung]}"
      
      # Skip already processed jobs
      if job[:description_saved] == true
        puts "✓ Job #{job[:id]} already processed successfully, skipping"
        next
      end
      
      begin
        # Navigate to the job detail page
        job_url = "https://interamt.de/koop/app/stellendetail?0&ID=#{job[:id]}"
        browser.goto job_url
        
        # Wait for page to load with more robust waiting strategy
        begin
          browser.wait_until(timeout: 30) { browser.ready_state == 'complete' }
          
          # Additional wait for content to load
          begin
            browser.wait_until(timeout: 15) do
              browser.div(class: /ia-e-richtext|ia-tab-primary/).exists? || 
              browser.div(role: 'main').exists?
            end
          rescue Watir::Wait::TimeoutError
            puts "⚠️ Content container not found, but proceeding with extraction anyway"
          end
        rescue Watir::Wait::TimeoutError
          puts "⚠️ Page load timeout, but proceeding with extraction anyway"
        end
        
        sleep 2  # Give JavaScript a moment to fully render
        
        # Try different selectors for job description content
        description_content = extract_job_description_content
        
        if description_content && !description_content.empty?
          # Save the content
          filename = save_job_description(job[:id], description_content)
          job[:description_saved] = true
          job[:description_file] = filename
          processed_count += 1
          puts "✓ Successfully extracted description for job #{job[:id]}"
        else
          puts "✗ Failed to extract description for job #{job[:id]}"
          job[:description_saved] = false
          job[:failure_reason] = "No content found"
          failed_count += 1
          take_screenshot("failed_description_#{job[:id]}_#{Time.now.to_i}.png")
        end
      rescue => e
        puts "✗ Error processing job #{job[:id]}: #{e.message}"
        job[:description_saved] = false
        job[:failure_reason] = e.message
        failed_count += 1
        take_screenshot("error_job_#{job[:id]}_#{Time.now.to_i}.png")
      end
      
      # Save checkpoint periodically
      if (actual_index + 1) % 10 == 0 || (actual_index + 1) % batch_size == 0
        puts "Progress: #{actual_index + 1}/#{job_data.length} jobs processed (#{processed_count} successful, #{failed_count} failed)"
        save_progress_checkpoint(job_data, processed_count, failed_count, actual_index)
      end
      
      # If we've processed a batch, take a short break to avoid overloading the server
      if (rel_index + 1) % batch_size == 0 && actual_index < job_data.length - 1
        puts "Batch complete. Taking a short break before continuing..."
        sleep 5
      end
    end
    
    # Final report
    puts "Job description processing complete!"
    puts "Total jobs: #{job_data.length}"
    puts "Successfully processed: #{processed_count}"
    puts "Failed to process: #{failed_count}"
    
    # Final checkpoint
    save_progress_checkpoint(job_data, processed_count, failed_count, job_data.length - 1, "complete")
    
    return job_data
  end
  
  # Load checkpoint for resuming job processing
  def load_checkpoint(checkpoint_path)
    if File.exist?(checkpoint_path)
      begin
        checkpoint_data = JSON.parse(File.read(checkpoint_path))
        puts "Loading checkpoint data from #{checkpoint_path}"
        return checkpoint_data
      rescue => e
        puts "Error loading checkpoint: #{e.message}"
        return nil
      end
    else
      puts "Checkpoint file not found at #{checkpoint_path}"
      return nil
    end
  end
  
  def process_job_descriptions(job_data, batch_size = 10, resume_from_index = 0)
    puts "Starting to process #{job_data.length} job descriptions"
    
    # Count processed and failed jobs
    processed_count = 0
    failed_count = 0
    
    # If resuming, count jobs already processed
    if resume_from_index > 0
      job_data.each_with_index do |job, idx|
        if idx < resume_from_index
          processed_count += 1 if job[:description_saved]
          failed_count += 1 if job.key?(:description_saved) && !job[:description_saved]
        end
      end
      puts "Resuming from index #{resume_from_index}. Already processed: #{processed_count} successful, #{failed_count} failed"
    end
    
    # Create directories for saving job details
    Dir.mkdir('job_details') unless Dir.exist?('job_details')
    
    # First, navigate to the main results page
    browser.goto URL
    
    # Wait for the page to load
    begin
      browser.wait_until(timeout: 30) { browser.ready_state == 'complete' }
    rescue Watir::Wait::TimeoutError
      puts "⚠️ Initial page load timeout"
    end
    
    # Process each job in batches
    job_data[resume_from_index..-1].each_slice(batch_size) do |job_batch|
      puts "Processing batch of #{job_batch.size} jobs"
      
      job_batch.each_with_index do |job, batch_index|
        actual_index = resume_from_index + batch_index
        puts "Processing job #{actual_index + 1}/#{job_data.length}: ID #{job[:id]}, Title: #{job[:stellenbezeichnung]}"
        
        # Skip already processed jobs
        if job[:description_saved] == true
          puts "✓ Job #{job[:id]} already processed successfully, skipping"
          next
        end
        
        begin
          # First, find the job in the results table by ID
          job_found = false
          max_attempts = 3
          attempts = 0
          
          while attempts < max_attempts && !job_found
            attempts += 1
            
            # Try to find the job row by ID
            job_row = nil
            begin
              browser.wait_until(timeout: 30) { browser.tbody.exists? }
              
              browser.tbody.trs.each do |row|
                row_id = nil
                row.tds.each do |td|
                  if td.attribute('data-field') == 'StellenangebotId'
                    row_id = td.span.text.strip
                    break
                  end
                end
                
                if row_id && row_id == job[:id]
                  job_row = row
                  job_found = true
                  break
                end
              end
            rescue => e
              puts "Error finding job row: #{e.message}"
            end
            
            if job_found
              puts "Found job #{job[:id]} in the results table, clicking on it"
              
              # Click on the row to open the job details
              begin
                job_row.click
                
                # Wait for the detail page to load
                browser.wait_until(timeout: 30) { browser.ready_state == 'complete' }
                
                # Additional wait for content to load
                begin
                  browser.wait_until(timeout: 15) do
                    browser.div(class: /ia-e-richtext|ia-tab-primary/).exists? || 
                    browser.div(role: 'main').exists?
                  end
                rescue Watir::Wait::TimeoutError
                  puts "⚠️ Content container not found, but proceeding with extraction anyway"
                end
                
                sleep 2  # Give JavaScript a moment to fully render
                
                # Extract job description content
                description_content = extract_job_description_content
                
                if description_content && !description_content.empty?
                  # Save the content
                  filename = save_job_description(job[:id], description_content)
                  job[:description_saved] = true
                  job[:description_file] = filename
                  processed_count += 1
                  puts "✓ Successfully extracted description for job #{job[:id]}"
                else
                  puts "✗ Failed to extract description for job #{job[:id]}"
                  job[:description_saved] = false
                  job[:failure_reason] = "No content found"
                  failed_count += 1
                  take_screenshot("failed_description_#{job[:id]}_#{Time.now.to_i}.png")
                end
                
                # Go back to the results page
                browser.goto URL
                
                # Wait for the results page to load again
                begin
                  browser.wait_until(timeout: 30) { browser.ready_state == 'complete' }
                rescue Watir::Wait::TimeoutError
                  puts "⚠️ Return to results page timeout"
                end
                
                # Wait for the table to load again
                begin
                  browser.wait_until(timeout: 30) { browser.tbody.exists? }
                rescue Watir::Wait::TimeoutError
                  puts "⚠️ Table not found after returning to results page"
                  # If we can't find the table, refresh the page
                  browser.refresh
                  sleep 3
                end
                
                # If we need to load more results to find our next job, do so
                load_more_results_for_batch(job_batch, batch_index)
                
              rescue => e
                puts "Error processing job after clicking: #{e.message}"
                job[:description_saved] = false
                job[:failure_reason] = e.message
                failed_count += 1
                take_screenshot("error_processing_#{job[:id]}_#{Time.now.to_i}.png")
                
                # Try to get back to the results page
                browser.goto URL
                sleep 3
              end
            else
              puts "⚠️ Job #{job[:id]} not found in current results, trying to load more results"
              
              # If we couldn't find the job, try to load more results
              if !click_load_more_button
                puts "No more results available - job not found"
                
                # If we've tried multiple times and still can't find it, use the direct URL approach as fallback
                if attempts == max_attempts
                  puts "Falling back to direct URL approach for job #{job[:id]}"
                  process_job_by_direct_url(job)
                  if job[:description_saved]
                    processed_count += 1
                  else
                    failed_count += 1
                  end
                end
              end
            end
          end
          
          # If we still couldn't find the job after multiple attempts, mark it as failed
          if !job_found && !job[:description_saved]
            puts "✗ Could not find job #{job[:id]} in results after #{max_attempts} attempts"
            job[:description_saved] = false
            job[:failure_reason] = "Job not found in results"
            failed_count += 1
          end
          
        rescue => e
          puts "✗ Error processing job #{job[:id]}: #{e.message}"
          job[:description_saved] = false
          job[:failure_reason] = e.message
          failed_count += 1
          take_screenshot("error_job_#{job[:id]}_#{Time.now.to_i}.png")
          
          # Try to get back to the results page
          browser.goto URL
          sleep 3
        end
        
        # Save checkpoint periodically
        if (actual_index + 1) % 10 == 0
          puts "Progress: #{actual_index + 1}/#{job_data.length} jobs processed (#{processed_count} successful, #{failed_count} failed)"
          save_progress_checkpoint(job_data, processed_count, failed_count, actual_index)
        end
      end
      
      # After processing a batch, save progress
      puts "Batch complete. Saving progress..."
      save_progress_checkpoint(job_data, processed_count, failed_count, resume_from_index + batch_size - 1)
      
      # Update resume_from_index for the next batch
      resume_from_index += batch_size
    end
    
    # Final report
    puts "Job description processing complete!"
    puts "Total jobs: #{job_data.length}"
    puts "Successfully processed: #{processed_count}"
    puts "Failed to process: #{failed_count}"
    
    # Final checkpoint
    save_progress_checkpoint(job_data, processed_count, failed_count, job_data.length - 1, "complete")
    
    return job_data
  end
  
  # Improved method to extract job description content
  def extract_job_description_content
    content = nil
    
    # Try multiple potential selectors for job description content in order of specificity
    selectors_to_try = [
      { type: :div, selector: { class: 'ia-e-richtext' }, name: "richtext class" },
      { type: :div, selector: { role: 'main' }, name: "main role" }
    ]
    
    selectors_to_try.each do |selector_info|
      begin
        element = browser.send(selector_info[:type], selector_info[:selector])
        if element.exists?
          content = element.html
          puts "Found description using #{selector_info[:name]} selector"
          break
        end
      rescue => e
        puts "Error trying #{selector_info[:name]} selector: #{e.message}"
      end
    end
    
    # If all else fails, get the body content
    if content.nil? || content.strip.empty?
      puts "No specific content container found, capturing full body content"
      begin
        content = browser.body.html
      rescue => e
        puts "Error capturing body content: #{e.message}"
        content = nil
      end
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
  
  # Method to save progress checkpoint with current index
  def save_progress_checkpoint(job_data, processed_count, failed_count, current_index, status = "in_progress")
    Dir.mkdir('job_checkpoints') unless Dir.exist?('job_checkpoints')
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    
    checkpoint_data = {
      timestamp: timestamp,
      status: status,
      total_jobs: job_data.length,
      processed_count: processed_count,
      failed_count: failed_count,
      current_index: current_index,
      jobs: job_data
    }
    
    filename = File.join('job_checkpoints', "job_progress_#{timestamp}.json")
    File.write(filename, JSON.generate(checkpoint_data))
    
    # Also save latest checkpoint
    latest_filename = File.join('job_checkpoints', "latest_checkpoint.json")
    File.write(latest_filename, JSON.generate(checkpoint_data))
    
    puts "Saved progress checkpoint to #{filename}"
  end

  # Existing methods below with minor improvements

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

  def extract_visible_job_info
    jobs = []

    begin
      if browser.tbody.exists?
        rows = browser.tbody.trs
        puts "Found #{rows.length} rows in tbody"

        rows.each_with_index do |row, row_index|
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

            # Only add if we have at least an ID
            if stellenangebot_id && !stellenangebot_id.empty?
              job = {
                id: clean_text(stellenangebot_id),
                behoerde: clean_text(behoerde || "Unknown"),
                stellenbezeichnung: clean_text(stellenbezeichnung || "Unknown"),
                processed: false
              }

              jobs << job
            else
              puts "Row #{row_index}: Could not extract job ID, skipping"
            end
          rescue => e
            puts "Error processing row #{row_index}: #{e.message}"
          end
        end
      else
        puts "No tbody found on page"
      end
    rescue => e
      puts "Error in extract_visible_job_info: #{e.message}"
      take_screenshot("error_extract_job_info_#{Time.now.to_i}.png")
    end

    puts "Extracted #{jobs.length} jobs from current page"
    jobs
  end

  def create_checkpoint(collected_jobs, processed_ids = [], current_phase = "id_collection", batch_number = 0)
    Dir.mkdir('job_scraper_checkpoints') unless Dir.exist?('job_scraper_checkpoints')
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

    # Get the last processed ID if any jobs have been processed
    last_processed_id = processed_ids.empty? ? nil : processed_ids.last

    # Calculate statistics
    total_ids_collected = collected_jobs.length
    details_fetched = processed_ids.length

    checkpoint_data = {
      timestamp: timestamp,
      last_processed_id: last_processed_id,
      current_phase: current_phase,
      batch_number: batch_number,
      statistics: {
        total_ids_collected: total_ids_collected,
        details_fetched: details_fetched,
        remaining_jobs: total_ids_collected - details_fetched
      },
      jobs: collected_jobs
    }

    # Create filename with phase and batch information
    filename = File.join('job_scraper_checkpoints', "checkpoint_#{current_phase}_batch#{batch_number}_#{timestamp}.json")
    File.write(filename, JSON.generate(checkpoint_data))

    # Also save a "latest" checkpoint file that's overwritten each time
    latest_filename = File.join('job_scraper_checkpoints', "checkpoint_latest.json")
    File.write(latest_filename, JSON.generate(checkpoint_data))

    puts "Saved checkpoint with #{total_ids_collected} jobs collected and #{details_fetched} details fetched to #{filename}"

    return filename
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
      results: 3,                    # default number of results
      job_postings: "process",       # default job postings mode: "process", "collect", or "extract"
      collect_count: 10_000,         # default number of job IDs to collect
      checkpoint_interval: 5,        # default checkpoint interval
      resume_checkpoint: nil,        # optional path to resume from checkpoint
      batch_size: 5                  # number of jobs to process in each batch before loading more
    }
  end

  def parse_options
    OptionParser.new do |opts|
      opts.banner = <<~BANNER
        Job Listing Web Scraper

        Basic Usage:
          ruby webscraper.rb --portal [bund|interamt] [options]

        Examples:
          # Process job details
          ruby webscraper.rb --portal interamt --keyword "Informatiker" --results 3
          ruby webscraper.rb --portal bund --keyword "Medieninformatiker" --results 5

          # Collect job IDs
          ruby webscraper.rb --portal interamt --job-postings collect --collect-count 5000
          ruby webscraper.rb --portal interamt --job-postings collect --checkpoint-interval 10
          ruby webscraper.rb --portal interamt --job-postings collect --resume-from checkpoint_latest.json

          # Extract job details from collected IDs
          ruby webscraper.rb --portal interamt --job-postings extract --resume-from job_scraper_checkpoints/checkpoint_latest.json
          ruby webscraper.rb --portal interamt --job-postings extract --resume-from job_checkpoints/latest_checkpoint.json --batch-size 10

        Available Options:
      BANNER

      opts.on("--portal PORTAL", ["bund", "interamt"],
              "Required. Specify which job portal to scrape",
              "  bund    - Service.bund.de portal",
              "  interamt - Interamt.de portal") do |portal|
        @options[:portal] = portal
      end

      opts.on("--keyword KEYWORD",
              "Search keyword for job listings",
              "Works for both portals",
              "Default: ''") do |keyword|
        @options[:keyword] = keyword
      end

      opts.on("--results N", Integer,
              "Number of results to process",
              "Default: 3") do |n|
        @options[:results] = n
      end

      # Update job-postings options
      opts.on("--job-postings MODE", ["process", "collect", "extract"],
              "Operation mode:",
              "  process - process job details on search results",
              "  collect - collect job IDs only",
              "  extract - extract details for previously collected job IDs",
              "Default: 'process'") do |mode|
        @options[:job_postings] = mode
      end

      # Add the missing collect-count option
      opts.on("--collect-count N", Integer,
              "Number of job IDs to collect in collect mode",
              "Default: 10000") do |n|
        @options[:collect_count] = n
      end

      # Add the missing checkpoint-interval option
      opts.on("--checkpoint-interval N", Integer,
              "How often to save checkpoints during collection (in batches)",
              "Default: 5") do |n|
        @options[:checkpoint_interval] = n
      end

      # Add the missing resume-from option
      opts.on("--resume-from FILE",
              "Resume from a checkpoint file",
              "Example: checkpoint_latest.json") do |file|
        @options[:resume_checkpoint] = file
      end

      # Add batch size option
      opts.on("--batch-size N", Integer,
              "Number of jobs to process in each batch (for extract mode)",
              "Default: 5") do |n|
        @options[:batch_size] = n
      end

    end.parse!

    validate_options
  end

  def validate_options
    unless @options[:portal]
      puts "Error: --portal option is required"
      puts "For help, use: ruby webscraper.rb --help"
      exit 1
    end

    if @options[:job_postings] == "collect" && @options[:portal] != "interamt"
      puts "Error: Collection mode is only supported for the interamt portal"
      exit 1
    end
    
    if @options[:job_postings] == "extract" && !@options[:resume_checkpoint]
      puts "Error: --resume-from option is required for extract mode"
      puts "Example: ruby webscraper.rb --portal interamt --job-postings extract --resume-from checkpoint_latest.json"
      exit 1
    end
  end

  def run
    parse_options

    begin
      case @options[:portal]
      when "bund"
        service_bund_page = site.service_bund_page
        if @options[:keyword] && !@options[:keyword].empty?
          service_bund_page.find_by_keyword(@options[:keyword])
        else
          puts "No keyword provided, processing default results"
        end
        service_bund_page.click_first_n_results(@options[:results])
      when "interamt"
        interamt_page = site.interamt_page

        case @options[:job_postings]
        when "collect"
          puts "Starting job ID collection mode (Phase 1)"
          puts "Target count: #{@options[:collect_count]}, Checkpoint interval: #{@options[:checkpoint_interval]}"

          collected_jobs = if @options[:resume_checkpoint]
            puts "Resuming from checkpoint: #{@options[:resume_checkpoint]}"
            interamt_page.collect_all_job_ids(@options[:collect_count], @options[:checkpoint_interval], @options[:resume_checkpoint])
          else
            interamt_page.collect_all_job_ids(@options[:collect_count], @options[:checkpoint_interval])
          end
          
          puts "Collection complete. Run extraction phase with:"
          puts "ruby webscraper.rb --portal interamt --job-postings extract --resume-from job_scraper_checkpoints/checkpoint_latest.json"
          
        when "extract"
          puts "Starting job details extraction mode (Phase 2)"

          # Load the job IDs from checkpoint
          checkpoint_path = @options[:resume_checkpoint]
          if File.exist?(checkpoint_path)
            checkpoint_data = interamt_page.load_checkpoint(checkpoint_path)
            
            if checkpoint_data && (checkpoint_data['jobs'] || checkpoint_data[:jobs])
              # Handle both string and symbol keys
              jobs = checkpoint_data['jobs'] || checkpoint_data[:jobs]
              puts "Loaded #{jobs.length} job IDs from checkpoint"
              
              # Process the jobs with the specified batch size
              interamt_page.process_collected_job_ids(jobs, @options[:batch_size])
            else
              puts "Failed to load job IDs from checkpoint: Invalid format"
              exit 1
            end
          else
            puts "Error: Checkpoint file not found: #{checkpoint_path}"
            exit 1
          end
          
        when "process"
          puts "Starting complete job collection and processing"
          
          # First collect job IDs
          collected_jobs = interamt_page.collect_all_job_ids(@options[:results])
          puts "Collected #{collected_jobs.length} job IDs, now processing job details"
          
          # Then process their descriptions
          interamt_page.process_job_descriptions(collected_jobs, @options[:batch_size])
        end
      end
    rescue => e
      puts "Error during execution: #{e.message}"
      puts e.backtrace
    ensure
      site.close
    end
  end
end

# Execute the script
if __FILE__ == $0
  ScraperCLI.new.run
end
