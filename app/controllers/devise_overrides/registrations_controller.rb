# devise_token_auth's registration endpoints (/auth). Every action, including
# PUT and DELETE /auth, is refused while Pathors login is on: Pathors owns the
# account, so neither a password sign-up, an account update, nor a self-deletion
# goes through here. With the switch off they behave as upstream.
class DeviseOverrides::RegistrationsController < DeviseTokenAuth::RegistrationsController
  include PathorsLoginGuard

  prepend_before_action :refuse_password_flow_for_pathors_login
end
