class ScraperController < ApplicationController
  def index
    # Display the form
  end

  def run
    # Get parameters from the form
    @portal = params[:portal] || "interamt"
    @keyword = params[:keyword]
    @max_jobs = params[:max_jobs].to_i || 50

    # Initialize status for the view
    @status = 'running'
    @job_data = []
    @error_message = nil

    # In a real application, we would run the scraper in a background job
    # For this demo, we'll simulate the scraper running
    begin
      # Create a new instance of the scraper service
      scraper = ScraperService.new(@portal, @keyword, @max_jobs)

      # Run the scraper and get the results
      @job_data = scraper.run
      @status = 'completed'
    rescue => e
      @status = 'error'
      @error_message = "Error: #{e.message}"
    end
  end
end
