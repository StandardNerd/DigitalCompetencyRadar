require 'watir'
require 'selenium-webdriver'
require 'set'

class ScraperService
  # Chrome options for headless environment
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

  def initialize(portal, keyword, max_jobs)
    @portal = portal
    @keyword = keyword
    @max_jobs = max_jobs.to_i
    @max_jobs = 50 if @max_jobs <= 0

    # Create output directory
    FileUtils.mkdir_p(Rails.root.join('public', 'job_details'))
  end

  def run
    # Validate portal
    unless @portal == "interamt"
      raise "Only interamt.de portal is supported"
    end

    begin
      # Initialize browser
      browser = Watir::Browser.new(:chrome, options: CHROME_OPTIONS)

      # Create site object
      site = Site.new(browser)

      # Get interamt page
      interamt_page = site.interamt_page

      # Apply keyword filter if provided
      if @keyword && !@keyword.empty?
        Rails.logger.info("Searching for keyword: #{@keyword}")
        # Add search keyword functionality here if needed
      end

      # Start extracting job descriptions
      Rails.logger.info("Starting job description extraction for up to #{@max_jobs} jobs")
      job_data = interamt_page.extract_job_descriptions(@max_jobs)

      # Save results summary to JSON
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      summary_file = Rails.root.join('public', "job_extraction_summary_#{timestamp}.json")

      summary_data = {
        total_jobs: job_data.length,
        successful: job_data.count { |j| j[:description_saved] },
        failed: job_data.count { |j| !j[:description_saved] },
        extraction_date: timestamp,
        jobs: job_data
      }

      File.write(summary_file, summary_data.to_json)
      Rails.logger.info("Saved results summary to #{summary_file}")

      return job_data
    rescue => e
      Rails.logger.error("Error in scraper: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      raise e
    ensure
      browser&.close
    end
  end

  # Navigation module
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
        Rails.logger.info("Found ia-e-button ia-js-cookie-accept__selected button, clicking it")
        begin
          cookie_accept_selected.click
          Rails.logger.info("Successfully clicked the cookie accept button")
          sleep 2
          return true
        rescue => e
          Rails.logger.error("Error clicking cookie accept button: #{e.message}")
          take_screenshot("cookie_button_click_error.png")
        end
      end

      if browser.element(id: 'cookie-modal-headline').exists?
        Rails.logger.info("Cookie modal detected with headline")
        cookie_buttons = browser.buttons

        accept_button = cookie_buttons.find do |btn|
          btn_text = btn.text.downcase
          btn_text.include?('accept') || btn_text.include?('ok') ||
          btn_text.include?('next') || btn_text.include?('agree') ||
          btn_text.include?('akzeptieren') || btn_text.include?('zustimmen')
        end

        if accept_button && accept_button.exists?
          Rails.logger.info("Clicking cookie acceptance button with text: #{accept_button.text}")
          accept_button.click
          sleep 2
          return true
        else
          Rails.logger.info("Cookie modal found but couldn't find the acceptance button")
          take_screenshot("cookie_modal_no_button.png")
        end
      end
    end
  end

  # Browser container class
  class BrowserContainer
    attr_reader :browser

    include Navigation

    def initialize(browser)
      @browser = browser
    end

    def close
      @browser.close
    end

    def take_screenshot(filename)
      path = Rails.root.join('public', 'job_details', filename)
      browser.screenshot.save(path)
      Rails.logger.info("Screenshot saved to #{path}")
    end

    def clean_text(text)
      text.to_s.strip.gsub(/\s+/, ' ')
    end
  end

  # Site class
  class Site < BrowserContainer
    def interamt_page
      @interamt_page ||= Interamt.new(browser)
    end
  end

  # Page class
  class Page < BrowserContainer
    include Navigation

    def initialize(browser, url)
      super(browser)
      goto(url)
    end
  end

  # Interamt class
  class Interamt < Page
    URL = "https://interamt.de/koop/app/trefferliste".freeze # All job listings

    def initialize(browser)
      super(browser, URL)
    end

    # Main method to run the extraction process
    def extract_job_descriptions(max_jobs = 200)
      Rails.logger.info("Starting direct job description extraction for up to #{max_jobs} jobs")

      job_data = []
      current_job_count = 0

      # Create directory for saving job details
      output_dir = Rails.root.join('public', 'job_details')
      FileUtils.mkdir_p(output_dir) unless Dir.exist?(output_dir)

      # Continue until we've processed enough jobs or can't find more
      while current_job_count < max_jobs
        Rails.logger.info("Processing batch of jobs (#{current_job_count}/#{max_jobs} completed so far)")

        # Wait for the table to load
        begin
          browser.wait_until(timeout: 30) { browser.tbody.exists? }
        rescue Watir::Wait::TimeoutError
          Rails.logger.info("Table not found after waiting 30 seconds - no more results or page error")
          take_screenshot("table_timeout_#{Time.now.to_i}.png")
          break
        end

        # Get all visible rows
        rows = browser.tbody.trs

        if rows.empty?
          Rails.logger.info("No job rows found on current page")
          break
        end

        Rails.logger.info("Found #{rows.length} job rows in current view")

        # Process each visible row
        rows.each_with_index do |row, index|
          # Break if we've reached the maximum
          if current_job_count >= max_jobs
            Rails.logger.info("Reached target of #{max_jobs} jobs")
            break
          end

          Rails.logger.info("Processing job row #{index + 1}/#{rows.length} (total processed: #{current_job_count + 1})")

          # Extract basic job info from row
          job_info = extract_job_info_from_row(row)

          if job_info
            # Click on the row to go to job details
            begin
              # Use JavaScript click as it's more reliable with table rows
              browser.execute_script("arguments[0].click();", row)
              Rails.logger.info("Clicked job row for: #{job_info[:stellenbezeichnung]}")

              # Wait for page to load
              browser.wait_until(timeout: 30) { browser.ready_state == 'complete' }
              sleep 2 # Give JavaScript a moment to fully render

              # Extract job description
              description_content = extract_job_description_content

              if description_content && !description_content.empty?
                # Save the content
                filename = save_job_description(job_info[:id], description_content)
                job_info[:description_file] = "/job_details/#{File.basename(filename)}"
                job_info[:description_saved] = true
                Rails.logger.info("✓ Successfully extracted description for job #{job_info[:id]}")
              else
                Rails.logger.info("✗ Failed to extract description for job #{job_info[:id]}")
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
              Rails.logger.error("✗ Error processing job row: #{e.message}")
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
            Rails.logger.info("No more results available - reached end of job listings")
            break
          end
        else
          break
        end
      end

      # Final report
      Rails.logger.info("Job description extraction complete!")
      Rails.logger.info("Total jobs processed: #{job_data.length}")
      Rails.logger.info("Successfully processed jobs: #{job_data.count { |j| j[:description_saved] }}")
      Rails.logger.info("Failed jobs: #{job_data.count { |j| !j[:description_saved] }}")

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
          Rails.logger.info("Could not extract job ID from row, skipping")
          return nil
        end
      rescue => e
        Rails.logger.error("Error extracting job info from row: #{e.message}")
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
        Rails.logger.info("Found description using richtext class selector")
      # Second approach: Look for the primary tab content
      elsif browser.div(id: 'ia-tab-primary').exists?
        content = browser.div(id: 'ia-tab-primary').html
        Rails.logger.info("Found description using primary tab selector")
      # Third approach: Look for description block with any class containing 'description'
      elsif browser.div(class: /description/).exists?
        content = browser.div(class: /description/).html
        Rails.logger.info("Found description using description class selector")
      # Fourth approach: Try to get the main content area
      elsif browser.div(role: 'main').exists?
        content = browser.div(role: 'main').html
        Rails.logger.info("Found description using main content role")
      end

      # If all else fails, get the body content
      if content.nil? || content.strip.empty?
        Rails.logger.info("No specific content container found, capturing full body content")
        content = browser.body.html
      end

      return content
    end

    # Method to save job description to file
    def save_job_description(job_id, content)
      timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
      filename = Rails.root.join('public', 'job_details', "job_#{job_id}_#{timestamp}.html")

      # Save HTML content
      File.write(filename, content)
      Rails.logger.info("Saved job description to #{filename}")

      # Take screenshot for verification
      screenshot_filename = Rails.root.join('public', 'job_details', "job_#{job_id}_screenshot_#{timestamp}.png")
      take_screenshot(screenshot_filename)

      return filename
    end

    def click_load_more_button
      Rails.logger.info("Looking for 'mehr laden' button...")
      load_more_button = nil

      # Try to find the load more button with different approaches
      if browser.button(text: /mehr laden/i).exists?
        load_more_button = browser.button(text: /mehr laden/i)
        Rails.logger.info("Found 'mehr laden' button by text")
      elsif browser.link(text: /mehr/i).exists?
        load_more_button = browser.link(text: /mehr/i)
        Rails.logger.info("Found 'mehr' link by text")
      elsif browser.element(class: /load-more/).exists?
        load_more_button = browser.element(class: /load-more/)
        Rails.logger.info("Found load more element by class")
      end

      if load_more_button && load_more_button.exists? && load_more_button.visible?
        begin
          Rails.logger.info("Clicking load more button")
          load_more_button.click
          sleep 2 # Wait for content to load
          return true
        rescue => e
          Rails.logger.error("Error clicking load more button: #{e.message}")
          take_screenshot("load_more_error_#{Time.now.to_i}.png")
          return false
        end
      else
        Rails.logger.info("No load more button found")
        return false
      end
    end
  end
end
