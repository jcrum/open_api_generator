class CreateGadgets < ActiveRecord::Migration[8.1]
  def change
    create_table :gadgets do |t|
      t.string :title, null: false
      t.string :description
      t.timestamps
    end
  end
end
