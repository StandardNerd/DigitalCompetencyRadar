class ScraperJob < ApplicationRecord
  belongs_to :user
  belongs_to :scraper_configuration
end
