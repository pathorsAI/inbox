// public/ files are served with a one-year max-age, so bump this whenever the
// favicon art changes or browsers keep showing the old icon. Keep it in sync with
// the favicon links in app/views/layouts/vueapp.html.erb.
const FAVICON_VERSION = '2';

export const showBadgeOnFavicon = () => {
  const favicons = document.querySelectorAll('.favicon');

  favicons.forEach(favicon => {
    const newFileName = `/favicon-badge-${favicon.sizes[[0]]}.png?v=${FAVICON_VERSION}`;
    favicon.href = newFileName;
  });
};

export const initFaviconSwitcher = () => {
  const favicons = document.querySelectorAll('.favicon');

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      favicons.forEach(favicon => {
        const oldFileName = `/favicon-${favicon.sizes[[0]]}.png?v=${FAVICON_VERSION}`;
        favicon.href = oldFileName;
      });
    }
  });
};
