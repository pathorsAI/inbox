class CreateCrmSyncEvents < ActiveRecord::Migration[7.1]
  def change
    create_table :crm_sync_events do |t|
      t.bigint :account_id, null: false
      t.bigint :hook_id, null: false
      t.string :provider, null: false
      t.bigint :contact_id
      t.string :action, null: false
      t.string :status, null: false
      t.text :message
      t.jsonb :details, null: false, default: {}
      t.datetime :created_at, null: false
    end
    add_index :crm_sync_events, [:hook_id, :created_at], order: { created_at: :desc }
    add_index :crm_sync_events, [:hook_id, :status, :created_at], order: { created_at: :desc }
  end
end
