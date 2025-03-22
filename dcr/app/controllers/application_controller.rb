class ApplicationController < ActionController::Base
  # Add CSRF protection
  protect_from_forgery with: :exception
end
