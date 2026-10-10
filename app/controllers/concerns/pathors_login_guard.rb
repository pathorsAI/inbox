# While the inbox signs people in through Pathors only (Pathors::Login), every
# path that sets, resets or checks a Chatwoot password is closed.
module PathorsLoginGuard
  private

  def refuse_password_flow_for_pathors_login
    render_pathors_login_only if Pathors::Login.enabled?
  end

  # A signed-in user adding an account carries no password; only the
  # unauthenticated signup that creates a password user is closed.
  def refuse_password_signup_for_pathors_login
    render_pathors_login_only if Pathors::Login.enabled? && current_user.nil?
  end

  def render_pathors_login_only(message_key = 'errors.pathors_login.password_disabled')
    render json: { error: I18n.t(message_key), error_code: 'pathors_login_only' }, status: :forbidden
  end
end
