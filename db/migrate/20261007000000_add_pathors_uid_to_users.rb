class AddPathorsUidToUsers < ActiveRecord::Migration[7.2]
  disable_ddl_transaction!

  def change
    add_column :users, :pathors_uid, :string
    add_index :users, :pathors_uid, unique: true, where: 'pathors_uid IS NOT NULL', algorithm: :concurrently
  end
end
