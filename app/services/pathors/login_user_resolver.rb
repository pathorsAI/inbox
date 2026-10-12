# Finds or creates the inbox user for a Pathors identity. The verified email is
# the account key: the same address is always the same inbox user, whichever
# Pathors identity (password or Google) it arrives with. The Pathors `sub` only
# follows the email, and finds the user when the address changed in Pathors.
class Pathors::LoginUserResolver
  # Raised with the login page error code as its message.
  class Refused < StandardError; end

  pattr_initialize [:uid!, :email!, :name, :email_verified]

  def perform
    raise Refused, 'pathors-email-unverified' unless email_verified == true && email.present?
    # A system user is Pathors' machine identity in one account, never a person.
    raise Refused, 'pathors-account-mismatch' if Pathors::Login::SYSTEM_USER_EMAIL.match?(email)

    user = User.from_email(email) || User.find_by(pathors_uid: uid) || create_user
    bind_uid(user)
  end

  private

  def bind_uid(user)
    return user if user.pathors_uid == uid

    User.transaction do
      User.where(pathors_uid: uid).where.not(id: user.id).update_all(pathors_uid: nil) # rubocop:disable Rails/SkipsModelValidations
      user.update!(pathors_uid: uid)
    end
    user
  end

  def create_user
    user = User.new(
      email: email,
      name: name.presence || email.split('@').first,
      password: "#{SecureRandom.hex(16)}aA1!"
    )
    user.skip_confirmation!
    user.save!
    user
  end
end
