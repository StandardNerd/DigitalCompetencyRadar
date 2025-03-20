require 'rails_helper'

RSpec.describe "ScheduledJobs", type: :request do
  describe "GET /index" do
    it "returns http success" do
      get "/scheduled_jobs/index"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /new" do
    it "returns http success" do
      get "/scheduled_jobs/new"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /create" do
    it "returns http success" do
      get "/scheduled_jobs/create"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /edit" do
    it "returns http success" do
      get "/scheduled_jobs/edit"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /update" do
    it "returns http success" do
      get "/scheduled_jobs/update"
      expect(response).to have_http_status(:success)
    end
  end

  describe "GET /destroy" do
    it "returns http success" do
      get "/scheduled_jobs/destroy"
      expect(response).to have_http_status(:success)
    end
  end

end
