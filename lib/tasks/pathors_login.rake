require 'csv'

namespace :pathors_login do
  desc 'Print human users as CSV, to see which are linked to a Pathors account (Pathors login links by email)'
  task audit: :environment do
    puts CSV.generate_line(%w[id email type confirmed pathors_uid accounts])
    User.includes(:accounts).find_each do |user|
      next if Pathors::Login.system_user?(user)

      accounts = user.accounts.map { |account| "#{account.id}:#{account.name}" }.join('; ').presence
      puts CSV.generate_line([user.id, user.email, user.type || 'User', user.confirmed?, user.pathors_uid, accounts])
    end
  end
end
