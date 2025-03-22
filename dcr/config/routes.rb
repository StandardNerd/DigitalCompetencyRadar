Rails.application.routes.draw do
  get 'scraper/index'
  post 'scraper/run'

  # Set the root path to the scraper index
  root 'scraper#index'
end
