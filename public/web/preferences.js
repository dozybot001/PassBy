/* Presentation only; authentication and product sessions stay independent. */
(() => {
  
  const root = document.documentElement;
  const parameters = new URLSearchParams(location.search);
  const read = (key) => { try { return localStorage.getItem(key); } catch { return null; } };
  const save = (key, value) => { try { localStorage.setItem(key, value); } catch { /* private browsing */ } };
  const theme = ['dark', 'light'].includes(parameters.get('theme')) ? parameters.get('theme') : read('passby.theme');
  const language = ['en', 'zh'].includes(parameters.get('lang')) ? parameters.get('lang') : read('passby.language');
  if (['dark', 'light'].includes(theme)) { root.dataset.theme = theme; save('passby.theme', theme); }
  if (['en', 'zh'].includes(language)) { root.dataset.uiLanguage = language; root.lang = language === 'zh' ? 'zh-CN' : 'en'; save('passby.language', language); }
})();
