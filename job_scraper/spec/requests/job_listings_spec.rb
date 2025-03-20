require 'rails_helper'

RSpec.describe "JobListings", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/job_listings/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /show" do
    it "returns http success" do
      get "/job_listings/show"
      expect(response).to have_http_status(:success)
    end
  end

end
