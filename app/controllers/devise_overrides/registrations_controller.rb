# devise_token_auth's sign-up and account-update endpoints (/auth). Kept as is,
# except that they set passwords, which Pathors login does not allow.
class DeviseOverrides::RegistrationsController < DeviseTokenAuth::RegistrationsController
  include PathorsLoginGuard

  prepend_before_action :refuse_password_flow_for_pathors_login
end
