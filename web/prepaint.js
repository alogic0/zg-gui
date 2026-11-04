// Classic script: presentation before styles/WASM, without listeners or globals.
(() => {
  const script = document.currentScript;
  const key = script.dataset.zgThemeKey;
  const fallback = script.dataset.zgThemeDefault || 'system';
  if (!/^[A-Za-z0-9_.-]{1,128}$/.test(key || '') || !['light','dark','system'].includes(fallback))
    throw new TypeError('Invalid pre-paint preference declaration');
  let theme = fallback === 'system' ? (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light') : fallback;
  try { const stored = localStorage.getItem(key); if (stored === 'light' || stored === 'dark') theme = stored; } catch {}
  document.documentElement.dataset.theme = theme;
})();
