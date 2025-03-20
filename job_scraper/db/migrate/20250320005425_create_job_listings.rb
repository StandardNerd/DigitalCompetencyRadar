class CreateJobListings < ActiveRecord::Migration[8.0]
  def change
    create_table :job_listings do |t|
      t.string :job_id
      t.string :portal
      t.string :title
      t.string :organization
      t.text :content
      t.string :url
      t.boolean :processed
      t.references :scraper_job, null: false, foreign_key: true

      t.timestamps
    end
  end
end
