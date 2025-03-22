require "test_helper"

class ScraperControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get scraper_index_url
    assert_response :success
  end

  test "should get run" do
    get scraper_run_url
    assert_response :success
  end
end
