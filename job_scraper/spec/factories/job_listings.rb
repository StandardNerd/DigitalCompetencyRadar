FactoryBot.define do
  factory :job_listing do
    job_id { "MyString" }
    portal { "MyString" }
    title { "MyString" }
    organization { "MyString" }
    content { "MyText" }
    url { "MyString" }
    processed { false }
    scraper_job { nil }
  end
end
