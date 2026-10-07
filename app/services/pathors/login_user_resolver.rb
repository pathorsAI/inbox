# Finds or creates the inbox user for a Pathors identity. The Pathors `sub` is
# the stable key; an existing user with the same verified email is linked on
# first sign-in, so people invited before the switch keep their accounts.
class Pathors::LoginUserResolver
  # Raised with the login page error code as its message.
  class Refused < StandardError; end

  pattr_initialize [:uid!, :email!, :name, :email_verified]

  def perform
    raise Refused, 'pathors-email-unverified' unless email_verified == true && email.present?

    User.find_by(pathors_uid: uid) || link_existing_user || create_user
  end

  private

  def link_existing_user
    user = User.from_email(email)
    return if user.nil?
    # A system user is Pathors' machine identity in one account, never a person.
    raise Refused, 'pathors-account-mismatch' if user.pathors_uid.present? || Pathors::Login.system_user?(user)

    user.update!(pathors_uid: uid)
    user
  end

  def create_user
    raise Refused, 'pathors-account-mismatch' if Pathors::Login::SYSTEM_USER_EMAIL.match?(email)

    user = User.new(
      email: email,
      name: name.presence || email.split('@').first,
      password: "#{SecureRandom.hex(16)}aA1!",
      pathors_uid: uid
    )
    user.skip_confirmation!
    user.save!
    user
  end
end
