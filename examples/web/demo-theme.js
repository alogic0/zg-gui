// Example-owned preference, loaded before styles to avoid a light page flash.
(() => {
  const key = 'zg-gui.demo.theme';
  const valid = value => value === 'light' || value === 'dark';
  const read = () => {
    try { const value = localStorage.getItem(key); return valid(value) ? value : 'light'; }
    catch { return document.documentElement.dataset.theme || 'light'; }
  };
  const paint = theme => {
    document.documentElement.dataset.theme = theme;
    document.querySelector('meta[name="theme-color"]')?.setAttribute('content', theme === 'dark' ? '#171a23' : '#f7f8fa');
  };
  paint(read());

  function bind({ root, app, action }) {
    const controller = new AbortController();
    const surface = () => app ? root.querySelector('[data-theme]') : document.documentElement;
    const button = root.querySelector('.theme-toggle');
    let observer;
    const apply = theme => {
      if (app && surface().dataset.theme !== theme) app.dispatch({ action });
      observer?.takeRecords();
      paint(theme);
      if (!app) {
        button.textContent = theme === 'dark' ? 'Light theme' : 'Dark theme';
        button.setAttribute('aria-label', `Use ${theme === 'dark' ? 'light' : 'dark'} theme`);
      }
    };
    const save = theme => {
      paint(theme);
      try { localStorage.setItem(key, theme); } catch { /* Themes still work without storage. */ }
    };
    apply(document.documentElement.dataset.theme);
    if (app) {
      observer = new MutationObserver(() => save(surface().dataset.theme));
      observer.observe(root, { subtree: true, attributes: true, attributeFilter: ['data-theme'] });
    } else {
      button.addEventListener('click', () => {
        const theme = surface().dataset.theme === 'dark' ? 'light' : 'dark';
        apply(theme);
        save(theme);
      }, { signal: controller.signal });
    }
    window.addEventListener('storage', event => {
      if (event.key === key || event.key === null) apply(read());
    }, { signal: controller.signal });
    window.addEventListener('pageshow', event => {
      if (event.persisted) apply(read());
    }, { signal: controller.signal });
    return () => { observer?.disconnect(); controller.abort(); };
  }
  window.demoTheme = Object.freeze({ bind });
  document.addEventListener('DOMContentLoaded', () => {
    if (document.querySelector('[data-source-theme]')) bind({ root: document });
  }, { once: true });
})();
