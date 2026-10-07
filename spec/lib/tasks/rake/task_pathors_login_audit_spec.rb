require 'rake'
require 'rails_helper'

RSpec.describe Rake::Task do
  subject(:task) { described_class['pathors_login:audit'] }

  before { task.reenable }

  it 'prints human users and their accounts, without Pathors system users' do
    account = create(:account, name: 'Acme, Inc')
    agent = create(:user, account: account, email: 'agent@example.com', pathors_uid: 'pathors-sub-1')
    create(:user, account: account, email: "system+acct#{account.id}@inbox.pathors.com")
    admin = create(:super_admin, email: 'ops@example.com')

    expect { task.invoke }.to output(<<~CSV).to_stdout
      id,email,type,confirmed,pathors_uid,accounts
      #{agent.id},agent@example.com,User,true,pathors-sub-1,"#{account.id}:Acme, Inc"
      #{admin.id},ops@example.com,SuperAdmin,true,,
    CSV
  end
end
