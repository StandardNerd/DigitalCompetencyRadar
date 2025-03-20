Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      get "scraper_jobs/create"
      get "scraper_jobs/show"
      get "scraper_jobs/update"
    end
  end
  get "scheduled_jobs/index"
  get "scheduled_jobs/new"
  get "scheduled_jobs/create"
  get "scheduled_jobs/edit"
  get "scheduled_jobs/update"
  get "scheduled_jobs/destroy"
  get "job_listings/index"
  get "job_listings/show"
  get "scraper_jobs/index"
  get "scraper_jobs/new"
  get "scraper_jobs/create"
  get "scraper_jobs/show"
  get "scraper_jobs/edit"
  get "scraper_jobs/update"
  get "scraper_jobs/destroy"
  get "dashboard/index"
  devise_for :users
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
