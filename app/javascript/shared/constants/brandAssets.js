// public/ is served with a one-year max-age (config/environments/production.rb),
// so a brand file whose artwork changes needs a new URL or returning browsers keep
// the old image. Bump this whenever favicons or brand-assets/* change, together
// with the hardcoded ?v= in: app/views/layouts/vueapp.html.erb (favicon links),
// config/installation_config.yml (LOGO, LOGO_DARK, LOGO_THUMBNAIL),
// app/views/super_admin/application/_navigation.html.erb,
// app/views/super_admin/devise/sessions/new.html.erb,
// app/views/installation/onboarding/index.html.erb and public/browserconfig.xml.
export const BRAND_ASSET_VERSION = '2';
