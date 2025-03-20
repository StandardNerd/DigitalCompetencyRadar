FactoryBot.define do
  factory :scraper_job do
    name { "MyString" }
    portal { "MyString" }
    keyword { "MyString" }
    results { 1 }
    mode { "MyString" }
    collect_count { 1 }
    checkpoint_interval { 1 }
    status { "MyString" }
    message { "MyText" }
    started_at { "2025-03-20 01:54:18" }
    completed_at { "2025-03-20 01:54:18" }
    user { nil }
    scraper_configuration { nil }
  end
end
