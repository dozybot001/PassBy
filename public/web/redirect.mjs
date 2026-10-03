const zh = new URLSearchParams(location.search).get('lang') === 'zh' || (!location.search && navigator.language.startsWith('zh'));
const title = document.getElementById('transition-title');
const status = document.getElementById('transition-status');
const message = document.getElementById('transition-message');
const actions = document.getElementById('transition-actions');
const retry = document.getElementById('transition-retry');
document.documentElement.lang = zh ? 'zh-Hans' : 'en';
retry.textContent = zh ? '重试' : 'Try again';
document.getElementById('transition-back').textContent = zh ? '返回 PassBy' : 'Return to PassBy';
let pending = false;
async function connect() {
  if (pending) return;
  pending = true;
  title.textContent = zh ? '正在前往 Tenon 登录…' : 'Connecting to Tenon…';
  document.title = title.textContent + ' · PassBy';
  message.textContent = zh ? '正在准备安全登录…' : 'Preparing secure sign-in…';
  status.classList.add('transition-progress');
  status.querySelector('.is-loading').hidden = false;
  actions.hidden = true;
  try {
    const response = await fetch(new URL('../api/auth/start?format=json', import.meta.url), { credentials: 'same-origin', cache: 'no-store', signal: AbortSignal.timeout(15000) });
    if (!response.ok) throw Error('Unavailable');
    const data = await response.json(), target = new URL(data.url);
    if (target.origin !== 'https://account.tenon.asia' || target.username || target.password || target.hash) throw Error('Invalid destination');
    location.replace(target.href);
  } catch {
    title.textContent = zh ? '暂时无法连接 Tenon' : 'Unable to connect to Tenon';
    message.textContent = zh ? '请检查网络后重试。' : 'Check your connection and try again.';
    status.querySelector('.is-loading').hidden = true;
    actions.hidden = false;
    pending = false;
  }
}
retry.addEventListener('click', connect);
void connect();
