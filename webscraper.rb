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

  def collect_all_job_ids(target_count = 10_000, checkpoint_interval = 5, resume_from = nil)
    # Initialize data structures
    collected_jobs = []
    batch_number = 0
    job_id_set = Set.new  # Use a Set for O(1) lookups when checking if ID exists

    # If resuming from a checkpoint
    if resume_from
      checkpoint_data = load_checkpoint(resume_from)
      if checkpoint_data
        collected_jobs = checkpoint_data['jobs']
        batch_number = checkpoint_data['batch_number'] + 1  # Start from next batch

        # Initialize the set with existing IDs for quick lookups
        collected_jobs.each do |job|
          job_id_set.add(job['id'])
        end

        puts "Resuming job collection from batch #{batch_number} with #{collected_jobs.length} jobs already collected"
      else
        puts "Could not load checkpoint file, starting fresh collection"
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

      # Add new jobs to collection, avoiding duplicates
      before_count = collected_jobs.length

      # Add only unique jobs
      new_jobs_added = 0
      new_jobs.each do |job|
        unless job_id_set.include?(job[:id])
          collected_jobs << job
          job_id_set.add(job[:id])
          new_jobs_added += 1
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
        puts "Reached target count of #{target_count} jobs"
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

    # Take a screenshot before clicking
    Dir.mkdir('screenshots') unless Dir.exist?('screenshots')
    take_screenshot("screenshots/before_clicking_load_more_#{Time.now.to_i}.png")

    # Click the button
    begin
      load_more_button.click
      puts "Clicked 'mehr laden' button"

      wait_time = 5
      puts "Waiting #{wait_time} seconds for new results to load..."
      sleep wait_time

      # Take a screenshot after clicking
      Dir.mkdir('screenshots') unless Dir.exist?('screenshots')
      take_screenshot("screenshots/after_clicking_load_more_#{Time.now.to_i}.png")

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

        # Debug the structure of the first row to validate our selectors
        if rows.length > 0
          first_row = rows[0]
          puts "First row HTML: #{first_row.html}"
          puts "First row TD count: #{first_row.tds.length}"
          first_row.tds.each_with_index do |td, index|
            puts "TD #{index} data-field: #{td.attribute('data-field')} | text: #{td.text}"
          end
        end

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

              puts "Row #{row_index}: Found job ID: #{job[:id]}"
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

  def save_checkpoint(collected_jobs)
    Dir.mkdir('job_id_checkpoints') unless Dir.exist?('job_id_checkpoints')
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

    checkpoint_data = {
      timestamp: timestamp,
      total_jobs_collected: collected_jobs.length,
      phase: "id_collection",
      jobs: collected_jobs
    }

    filename = File.join('job_id_checkpoints', "job_ids_#{timestamp}.json")
    File.write(filename, JSON.generate(checkpoint_data))
    puts "Saved checkpoint with #{collected_jobs.length} jobs to #{filename}"
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

  def load_checkpoint(filename = nil)
    # If no filename is provided, try to load the latest checkpoint
    if filename.nil?
      latest_file = File.join('job_scraper_checkpoints', "checkpoint_latest.json")
      if File.exist?(latest_file)
        filename = latest_file
      else
        puts "No checkpoint file specified and no latest checkpoint found."
        return nil
      end
    end

    begin
      checkpoint_data = JSON.parse(File.read(filename))
      puts "Loaded checkpoint from #{filename}"
      puts "Phase: #{checkpoint_data['current_phase']}, Batch: #{checkpoint_data['batch_number']}"
      puts "Statistics: #{checkpoint_data['statistics']['total_ids_collected']} jobs collected, #{checkpoint_data['statistics']['details_fetched']} details fetched"

      return checkpoint_data
    rescue => e
      puts "Error loading checkpoint: #{e.message}"
      return nil
    end
  end

  # Update load_more_results to return whether more results are available
  def load_more_results(times = 1)
    puts "Attempting to load more results..."
    times_clicked = 0

    times.times do |i|
      # Look for the "mehr laden" button using multiple selectors
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

      # If we can't find the button or it's not visible, we've reached the end
      if load_more_button.nil? || !load_more_button.exists? || !load_more_button.visible?
        puts "No more 'mehr laden' button found after #{times_clicked} clicks."
        return false
      end

      # Click the button
      load_more_button.click
      times_clicked += 1
      puts "Clicked 'mehr laden' button (#{i+1}/#{times})"
      sleep 2

      # Wait for new results to load
      wait_time = 2 + rand(3)
      puts "Waiting #{wait_time} seconds for new results to load..."
      sleep wait_time
    end

    puts "Finished loading more results. Clicked #{times_clicked} times."
    return true  # More results might be available
  end

  def click_first_n_results(n, keyword = "")
    if n < 1
      raise ArgumentError, "n must be greater than or equal to 1"
    end

    begin
      puts "Waiting for page to load completely..."
      browser.wait_until(timeout: 30) { browser.ready_state == 'complete' }

      search_field = nil

      if browser.text_field(id: 'id43').exists?
        puts "Found search field by ID: id43"
        search_field = browser.text_field(id: 'id43')
      elsif browser.text_field(name: /suche|search/i).exists?
        puts "Found search field by name"
        search_field = browser.text_field(name: /suche|search/i)
      elsif browser.text_field(placeholder: /suche|search/i).exists?
        puts "Found search field by placeholder"
        search_field = browser.text_field(placeholder: /suche|search/i)
      else
        puts "Trying to find any available text fields..."
        all_text_fields = browser.text_fields
        puts "Found #{all_text_fields.length} text fields"

        if all_text_fields.length > 0
          search_field = all_text_fields.first
          puts "Using first available text field"
        end
      end

      if search_field && search_field.exists?
        puts "Setting keyword: #{keyword}"
        search_field.set keyword
        search_field.send_keys :enter

        puts "Waiting for search results..."
        browser.wait_until(timeout: 30) { browser.tbody.exists? || browser.div(text: /keine ergebnisse|no results/i).exists? }

        take_screenshot("interamt_open_positions.png")

        if browser.tbody.exists?
          results = browser.tbody
          puts "Result html: #{results.html}"

          rows = results.trs
          puts "Found #{rows.length} results"

          num_to_process = [n, rows.length].min
          puts "Will process #{num_to_process} results"

          (0...num_to_process).each do |index|
            puts "Clicking row #{index + 1}"

            current_row = browser.tbody.tr(index: index)
            if current_row.exists?
              current_row.click
              job_listing_description(index + 1)
              browser.back
              browser.wait_until(timeout: 30) { browser.tbody.present? }
            else
              puts "Row #{index + 1} no longer exists, skipping"
            end
          end
        else
          puts "No results found"
          take_screenshot("interamt_no_results.png")
        end
      else
        puts "Could not find search field"
        take_screenshot("interamt_no_search_field.png")
        raise "Could not find search field on the page. Check screenshot: interamt_no_search_field.png"
      end
    rescue Watir::Wait::TimeoutError => e
      puts "Timeout error: #{e.message}"
      take_screenshot("interamt_timeout_error.png")
      raise "Operation timed out. Check screenshot: interamt_timeout_error.png"
    rescue => e
      puts "Error: #{e.message}"
      take_screenshot("interamt_error.png")
      raise "An error occurred: #{e.message}. Check screenshot: interamt_error.png"
    end
  end

  def process_collected_job_ids(job_ids_to_process, batch_size = 5)
    puts "Starting to process #{job_ids_to_process.length} collected job IDs"
    processed_ids = []
    failed_ids = []

    # Track original page state to handle pagination
    current_batch = 0

    # Continue until all job IDs are processed
    while processed_ids.length + failed_ids.length < job_ids_to_process.length
      puts "Processing batch #{current_batch + 1}, progress: #{processed_ids.length + failed_ids.length}/#{job_ids_to_process.length}"

      # Wait for the results table to load
      begin
        browser.wait_until(timeout: 30) { browser.tbody.exists? }
      rescue Watir::Wait::TimeoutError
        puts "Table not found after waiting 30 seconds - page error"
        take_screenshot("table_timeout_phase2_#{Time.now.to_i}.png")
        break
      end

      # Get all visible job listings on current page
      visible_jobs = extract_visible_job_info
      puts "Found #{visible_jobs.length} visible jobs on current page"

      # Check each visible job against our target list
      processed_in_this_batch = 0
      visible_jobs.each do |visible_job|
        job_id = visible_job[:id]

        # Check if this job ID is in our target list and hasn't been processed yet
        target_job = job_ids_to_process.find { |j| j[:id] == job_id && !j[:processed] }

        if target_job
          puts "Found target job ID: #{job_id} - processing details"

          # Find the row containing this job ID and click it
          begin
            # Find the row by job ID
            job_row = nil
            browser.tbody.trs.each do |row|
              if row.tds.any? { |td| td.text.strip == job_id }
                job_row = row
                break
              end
            end

            if job_row
              puts "Clicking on job row for ID: #{job_id}"
              job_row.click

              # Wait for job detail page to load
              browser.wait_until(timeout: 30) {
                browser.div(class: 'ia-e-richtext ia-h-space--top-l').exists? ||
                browser.div(id: 'ia-tab-primary').exists?
              }

              # Extract the rich text content
              rich_text_content = extract_rich_text_content
              if rich_text_content
                # Save the rich text content to a file
                save_job_details(job_id, rich_text_content)
                puts "Successfully extracted and saved details for job ID: #{job_id}"
                processed_ids << job_id
                target_job[:processed] = true
                processed_in_this_batch += 1
              else
                puts "Failed to extract rich text content for job ID: #{job_id}"
                failed_ids << job_id
              end

              # Navigate back to the listing page
              browser.back

              # Wait for the listing page to reload
              browser.wait_until(timeout: 30) { browser.tbody.exists? }
              sleep 2 # Give the page a moment to stabilize
            else
              puts "Could not find row for job ID: #{job_id}"
              failed_ids << job_id
            end
          rescue => e
            puts "Error processing job ID #{job_id}: #{e.message}"
            take_screenshot("error_processing_job_#{job_id}_#{Time.now.to_i}.png")
            failed_ids << job_id

            # Try to navigate back to the listing page if we're stuck on a detail page
            if !browser.tbody.exists?
              browser.back
              browser.wait_until(timeout: 30) { browser.tbody.exists? }
              sleep 2
            end
          end
        end

        # Check if we've processed enough in this batch
        if processed_in_this_batch >= batch_size
          puts "Reached batch limit of #{batch_size} jobs, will load more results"
          break
        end
      end

      # Save checkpoint after each batch
      create_checkpoint(job_ids_to_process, processed_ids, "details_extraction", current_batch)

      # If we've processed all visible jobs that match our target list,
      # or haven't processed any in this batch, load more results
      if processed_in_this_batch == 0 || processed_in_this_batch < batch_size
        puts "Loading more results to find remaining target jobs"
        if !click_load_more_button
          puts "No more results available - reached end of job listings"
          break
        end
      end

      current_batch += 1
    end

    # Final checkpoint
    create_checkpoint(job_ids_to_process, processed_ids, "details_extraction_complete", current_batch)

    puts "Job processing complete!"
    puts "Successfully processed: #{processed_ids.length} jobs"
    puts "Failed to process: #{failed_ids.length} jobs"

    return {
      processed: processed_ids,
      failed: failed_ids
    }
  end

  def save_job_details(job_id, rich_text_content)
    Dir.mkdir('job_details') unless Dir.exist?('job_details')
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

    # Save the rich text content
    filename = File.join('job_details', "job_#{job_id}_#{timestamp}.html")
    File.write(filename, rich_text_content)
    puts "Saved job details to #{filename}"
  end

  def extract_rich_text_content
    rich_text_div = browser.div(class: 'ia-e-richtext ia-h-space--top-l')
    if rich_text_div.exists?
      puts "Found rich text content div"
      content_html = rich_text_div.html
      return content_html
    else
      puts "Rich text content div not found"
      return nil
    end
  rescue => e
    puts "Error extracting rich text content: #{e.message}"
    take_screenshot("error_extracting_rich_text.png")
    return nil
  end

  def job_listing_description(row_number)
    Dir.mkdir('scraped_data_interamt') unless Dir.exist?('scraped_data_interamt')
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

    html_filename = File.join('scraped_data_interamt', "job_#{row_number}_#{timestamp}.html")
    rich_text_filename = File.join('scraped_data_interamt', "job_#{row_number}_richtext_#{timestamp}.html")
    screenshot_filename = File.join('scraped_data_interamt', "job_#{row_number}_#{timestamp}.png")

    puts "Taking screenshot: #{screenshot_filename}"
    take_screenshot(screenshot_filename)

    # Extract and save the full content as before
    content = browser.div(id: 'ia-tab-primary').text
    content_html = browser.div(id: 'ia-tab-primary').html
    File.write(html_filename, content_html)

    # Extract and save the rich text content specifically
    rich_text_content = extract_rich_text_content
    if rich_text_content
      File.write(rich_text_filename, rich_text_content)
      puts "Saved rich text content to #{rich_text_filename}"
    else
      puts "No rich text content found for row #{row_number}"
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

class ServiceBund < Page
  URL = "https://www.service.bund.de/Content/DE/Stellen/Suche/Formular.html".freeze

  def initialize(browser)
    super(browser, URL)
  end

  def take_screenshot(filename, y=2600)
    browser.window.resize_to(1200, y)
    browser.screenshot.save filename
  rescue => e
    puts "Failed to take screenshot #{filename}: #{e.message}"
  end

  def click_first_n_results(n)
    begin
      results_list = browser.ul(class: 'result-list')
      results_list.wait_until(&:present?)
      take_screenshot("bund_open_positions.png")

      results = results_list.lis
      available_results = results.length
      puts "Found #{available_results} results available"

      n = [n, available_results].min
      puts "Will process first #{n} results"

      n.times do |i|
        puts "\nProcessing result #{i + 1} of #{n}"

        current_link = browser.ul(class: 'result-list').lis[i].a
        current_link.wait_until(&:present?)

        puts "Clicking result #{i + 1}"
        current_link.click

        browser.div(class: 'text').wait_until(&:present?)

        result = parse_second_section_content(i + 1)
        puts "Job Listing #{i + 1}: #{result}"
        puts "--------------------"

        puts "Navigating back to results page"
        browser.back

        results_list.wait_until(&:present?)
      end
    rescue Watir::Wait::TimeoutError => e
      puts "Timeout while processing results: #{e.message}"
      take_screenshot("results_timeout_error.png")
      raise "Results processing timed out. Check screenshot: results_timeout_error.png"
    rescue => e
      puts "Error while processing results: #{e.message}"
      take_screenshot("results_error.png")
      raise "Results processing failed. Check screenshot: results_error.png"
    end
  end


  def find_by_keyword(keyword="")
      puts "Searching for keyword: #{keyword}"
      begin
        input_field = browser.div(class: 'form-item item-l').input
        input_field.wait_until(&:present?)
        input_field.set keyword
        input_field.send_keys :enter

        Watir::Wait.until(timeout: 10) do
          browser.ul(class: 'result-list').present? ||
          browser.div(class: 'no-results').present? ||
          browser.section(class: 'result').present?
        end

        if browser.section(class: 'result').present? &&
           browser.section(class: 'result').text.include?('Keine Treffer')
          puts "No results found for keyword: #{keyword}"
          take_screenshot("no_results.png")
          exit
        else
          result_count = browser.ul(class: 'result-list').lis.length
          puts "Found #{result_count} results for keyword: #{keyword}"
          return true
        end
      rescue Watir::Wait::TimeoutError => e
        puts "Timeout while searching: #{e.message}"
        take_screenshot("search_timeout_error.png")
        raise "Search operation timed out. Check screenshot: search_timeout_error.png"
      rescue => e
        puts "Error during search: #{e.message}"
        take_screenshot("search_error.png")
        raise "Search operation failed. Check screenshot: search_error.png"
      end
    end

  def parse_second_section_content(id)
    puts "Parsing content for result #{id}"
    begin
      browser.div(class: 'text').wait_until(&:present?)

      sections = browser.div(class: 'text').sections
      puts "Found #{sections.length} sections"

      Dir.mkdir('scraped_data_bund') unless Dir.exist?('scraped_data_bund')

      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

      html_filename = File.join('scraped_data_bund', "job_#{id}_#{timestamp}.html")
      screenshot_filename = File.join('scraped_data_bund', "job_#{id}_#{timestamp}.png")

      puts "Taking screenshot: #{screenshot_filename}"
      take_screenshot(screenshot_filename)

      if sections.length >= 2
        second_section_html = sections[1].html.strip
        puts "Extracted second section HTML (length: #{second_section_html.length})"

        if second_section_html.empty? || second_section_html.match(/^\s*<section>\s*(?:<!--[\s\S]*?-->)?\s*<\/section>\s*$/m)
          puts "Second section is empty or contains only comments"

          if sections.length >= 3
            puts "Checking third section for URL"
            third_section = sections[3]
            url_link = third_section.a(href: /.*/)

            if url_link.exists?
              url = url_link.href
              content = "<p>URL from third section: <a href=\"#{url}\">#{url}</a></p>"
              File.write(html_filename, content)
              return "Second section was empty, saved URL from third section to #{html_filename}"
            end
          end

          File.write(html_filename, "<p>Second section contains only comments, no useful content found</p>")
          return "Second section empty or contains only comments, saved to #{html_filename}"
        else
          File.write(html_filename, second_section_html)
          return "Saved section content to #{html_filename}"
        end
      else
        File.write(html_filename, "<p>Second section not found</p>")
        return "Second section not found, created empty file #{html_filename}"
      end
    rescue => e
      puts "Error parsing content: #{e.message}"
      take_screenshot("parsing_error_#{id}.png")
      raise "Content parsing failed for result #{id}. Check screenshot: parsing_error_#{id}.png"
    end
  end
end

class ScraperCLI
  include SiteHelper

  def initialize
    @options = {
      portal: nil,
      keyword: "",
      results: 3,                    # default number of results
      mode: "process",               # default mode: "process", "collect", or "extract"
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
          ruby webscraper.rb --portal interamt --mode collect --collect-count 5000
          ruby webscraper.rb --portal interamt --mode collect --checkpoint-interval 10
          ruby webscraper.rb --portal interamt --mode collect --resume-from checkpoint_latest.json

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

      # Update mode options
      opts.on("--mode MODE", ["process", "collect", "extract"],
              "Operation mode:",
              "  process - process job details on search results",
              "  collect - collect job IDs only",
              "  extract - extract details for previously collected job IDs",
              "Default: 'process'") do |mode|
        @options[:mode] = mode
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

    if @options[:mode] == "collect" && @options[:portal] != "interamt"
      puts "Error: Collection mode is only supported for the interamt portal"
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

        case @options[:mode]
        when "collect"
          puts "Starting job ID collection mode (Phase 1)"
          puts "Target count: #{@options[:collect_count]}, Checkpoint interval: #{@options[:checkpoint_interval]}"

          if @options[:resume_checkpoint]
            puts "Resuming from checkpoint: #{@options[:resume_checkpoint]}"
            interamt_page.collect_all_job_ids(@options[:collect_count], @options[:checkpoint_interval], @options[:resume_checkpoint])
          else
            interamt_page.collect_all_job_ids(@options[:collect_count], @options[:checkpoint_interval])
          end
        when "extract"
          puts "Starting job details extraction mode (Phase 2)"

          # Load the job IDs from checkpoint
          if @options[:resume_checkpoint]
            checkpoint_data = interamt_page.load_checkpoint(@options[:resume_checkpoint])
            if checkpoint_data && checkpoint_data['jobs']
              puts "Loaded #{checkpoint_data['jobs'].length} job IDs from checkpoint"
              interamt_page.process_collected_job_ids(checkpoint_data['jobs'], @options[:batch_size])
            else
              puts "Failed to load job IDs from checkpoint"
              exit 1
            end
          else
            puts "Error: --resume-checkpoint option is required for extract mode"
            exit 1
          end
        when "process"
          puts "Starting job processing mode"
          interamt_page.click_first_n_results(@options[:results], @options[:keyword])
        end
      end
    ensure
      site.close
    end
  end
end

# Execute the script
if __FILE__ == $0
  ScraperCLI.new.run
end
