FactoryBot.define do
  factory :scraper_configuration do
    name { "MyString" }
    portal_type { "MyString" }
    default_keyword { "MyString" }
    default_results { 1 }
    collect_count { 1 }
    checkpoint_interval { 1 }
    active { false }
  end
end
