require 'watir'
require 'selenium-webdriver'
require 'optparse'

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
  # URL = "https://interamt.de/koop/app/trefferliste".freeze # All job listings
  URL = "https://interamt.de/koop/app/stellensuche".freeze # Job search page

  def initialize(browser)
    super(browser, URL)
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

  def job_listing_description(row_number)
    Dir.mkdir('scraped_data_interamt') unless Dir.exist?('scraped_data_interamt')
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')

    html_filename = File.join('scraped_data_interamt', "job_#{row_number}_#{timestamp}.html")
    screenshot_filename = File.join('scraped_data_interamt', "job_#{row_number}_#{timestamp}.png")

    puts "Taking screenshot: #{screenshot_filename}"
    take_screenshot(screenshot_filename)

    content = browser.div(id: 'ia-tab-primary').text
    content_html = browser.div(id: 'ia-tab-primary').html

    puts "Content for row #{row_number}: #{content}"
    File.write(html_filename, content_html)
  end

  def clean_text(text)
    return nil if text.nil?
    text.strip.gsub(/\s+/, ' ')
  end

  def take_screenshot(filename)
    browser.window.resize_to(1200, 1600)

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

  def take_screenshot(filename)
    browser.window.resize_to(1200, 2600)
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
      results: 3                  # default number of results
    }
  end

  def parse_options
    OptionParser.new do |opts|
      opts.banner = <<~BANNER
        Job Listing Web Scraper

        Basic Usage:
          ruby webscraper.rb --portal [bund|interamt] [options]

        Examples:
          ruby webscraper.rb --portal interamt --keyword "Informatiker" --results 3
          ruby webscraper.rb --portal bund --keyword "Medieninformatiker" --results 5
          ruby webscraper.rb --portal interamt --results 2
          ruby webscraper.rb --portal bund

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

      opts.on_tail("--help", "Show this help message") do
        puts opts
        exit
      end

      opts.on_tail("--version", "Show version") do
        puts "Job Listing Web Scraper v1.0.0"
        exit
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
        interamt_page.click_first_n_results(@options[:results], @options[:keyword])
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
