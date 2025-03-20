class CreateScraperJobs < ActiveRecord::Migration[8.0]
  def change
    create_table :scraper_jobs do |t|
      t.string :name
      t.string :portal
      t.string :keyword
      t.integer :results
      t.string :mode
      t.integer :collect_count
      t.integer :checkpoint_interval
      t.string :status
      t.text :message
      t.datetime :started_at
      t.datetime :completed_at
      t.references :user, null: false, foreign_key: true
      t.references :scraper_configuration, null: false, foreign_key: true

      t.timestamps
    end
  end
end
