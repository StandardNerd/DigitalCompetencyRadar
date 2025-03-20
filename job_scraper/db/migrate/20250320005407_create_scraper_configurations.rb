class CreateScraperConfigurations < ActiveRecord::Migration[8.0]
  def change
    create_table :scraper_configurations do |t|
      t.string :name
      t.string :portal_type
      t.string :default_keyword
      t.integer :default_results
      t.integer :collect_count
      t.integer :checkpoint_interval
      t.boolean :active

      t.timestamps
    end
  end
end
