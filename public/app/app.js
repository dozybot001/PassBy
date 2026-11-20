// PassBy in a browser: a guest of PassBy on a phone, over the local network (docs/sync.md 7).
// The notebook lives in this page's memory only. It is never written to storage, and it is sent
// nowhere except, sealed, to the phone the person entered. Entry text is untrusted: it only ever
// goes into the page as text.
import { Session, canonicalCode, privateAddress } from '/app/sync.js';

const zh = (navigator.language || '').toLowerCase().startsWith('zh');
document.documentElement.lang = zh ? 'zh-Hans' : 'en';
const T = zh ? {
  title: '在电脑上用 PassBy', privacy: '隐私政策', terms: '用户协议',
  intro: '这个页面连到你手机上的 PassBy，在同一个 Wi-Fi 里同步。内容加密后只在这台电脑和你的手机之间传，不经过我们的服务器；页面不把密码本存在电脑上，关掉就没有了。',
  steps: ['手机和电脑连同一个 Wi-Fi。', '在手机的 PassBy 里打开「设置 › 同步」，点「让别的设备连过来」。', '把手机上显示的地址和配对码填在下面。浏览器问是否允许访问本地网络时，选允许。'],
  address: '地址', code: '配对码', connect: '连接', connecting: '正在连接…',
  browser: '这个页面要用电脑上的 Chrome 或 Edge（142 或更新的版本）打开。别的浏览器不让网页连接局域网里的设备。',
  denied: '浏览器现在不允许这个页面访问本地网络。点地址栏左边的图标，把「本地网络访问」改成允许，再试一次。',
  badAddress: '地址是手机上显示的那一串，像 192.168.1.20:52814。',
  badCode: '配对码是 12 位字母和数字。',
  errors: {
    unreachable: '连不上手机。确认手机和电脑在同一个 Wi-Fi，手机上的同步页面开着，并且浏览器允许了访问本地网络。',
    wrongCode: '手机没有接受。配对码不对，或者这个配对码已经用过了：在手机上重新点「让别的设备连过来」，用新的配对码再连。',
    stopped: '手机已经停止，请在手机上重新开始。',
    untrusted: '对方的回复验证不过，已断开，没有发送任何内容。',
    failed: '手机没能完成这次同步，没有做任何改动。把手机上的 PassBy 更新到最新再试。',
  },
  connected: a => `已连到 ${a}。保存和删除会立刻同步到手机；手机上的同步页面要一直开着。`,
  disconnect: '断开并清除', refresh: '从手机刷新', search: '搜索', all: '全部', unfiled: '未分组',
  add: '新建密码', empty: '还没有密码。', noMatch: '没有找到。', pick: '在左边选一条，或者新建。',
  untitled: '未命名', noAccount: '未填写账户',
  fTitle: '标题', fAccount: '账户', fPassword: '密码', fNotes: '备注', fFolder: '文件夹',
  copy: '复制', copied: '已复制', show: '显示', hide: '隐藏', edit: '编辑', remove: '删除', save: '保存', cancel: '取消',
  clipboard: '浏览器不会自动清除剪贴板。只在你自己的电脑上复制密码。',
  confirmRemove: t => `删除「${t}」？它会进手机上的「最近删除」，30 天内可以放回。`,
  saving: '正在同步…', notSaved: '没有保存：',
  lost: '和手机的连接断了，页面里的内容已清除。请重新连接。',
  conflicts: n => `有 ${n} 条两边都改过，两份都留下了：标题带「冲突副本」的是另一份。`,
} : {
  title: 'PassBy on a computer', privacy: 'Privacy policy', terms: 'Terms of Service',
  intro: 'This page connects to PassBy on your phone and syncs over the same Wi-Fi. What is sent is encrypted and goes only between this computer and your phone, never through our servers. The page keeps no copy of your notebook on the computer; closing it clears everything.',
  steps: ['Put your phone and computer on the same Wi-Fi.', 'In PassBy on your phone, open Settings › Sync and tap "Let another device connect".', 'Enter the address and pairing code your phone shows. When the browser asks to access your local network, allow it.'],
  address: 'Address', code: 'Pairing code', connect: 'Connect', connecting: 'Connecting…',
  browser: 'Open this page in Chrome or Edge on a computer (version 142 or later). Other browsers do not let a web page reach devices on your local network.',
  denied: 'The browser is not letting this page reach your local network. Click the icon to the left of the address bar, set "Local network access" to Allow, and try again.',
  badAddress: 'The address is the one your phone shows, like 192.168.1.20:52814.',
  badCode: 'The pairing code is 12 letters and digits.',
  errors: {
    unreachable: 'Could not reach your phone. Check that both are on the same Wi-Fi, that the sync page is open on the phone, and that the browser was allowed to access your local network.',
    wrongCode: 'Your phone did not accept. The code is wrong, or it has already been used: tap "Let another device connect" again on the phone and use the new code.',
    stopped: 'Your phone has stopped. Start again on the phone.',
    untrusted: 'The reply could not be verified. Disconnected; nothing was sent.',
    failed: 'Your phone could not finish this sync and nothing was changed. Update PassBy on the phone and try again.',
  },
  connected: a => `Connected to ${a}. Saving and deleting sync to your phone at once; keep the sync page open on the phone.`,
  disconnect: 'Disconnect and clear', refresh: 'Refresh from phone', search: 'Search', all: 'All', unfiled: 'Unfiled',
  add: 'New password', empty: 'No passwords yet.', noMatch: 'Nothing found.', pick: 'Choose an entry on the left, or add one.',
  untitled: 'Untitled', noAccount: 'No account',
  fTitle: 'Title', fAccount: 'Account', fPassword: 'Password', fNotes: 'Notes', fFolder: 'Folder',
  copy: 'Copy', copied: 'Copied', show: 'Show', hide: 'Hide', edit: 'Edit', remove: 'Delete', save: 'Save', cancel: 'Cancel',
  clipboard: 'The browser does not clear the clipboard for you. Copy passwords only on your own computer.',
  confirmRemove: t => `Delete "${t}"? It goes to Recently Deleted on your phone and can be put back within 30 days.`,
  saving: 'Syncing…', notSaved: 'Not saved: ',
  lost: 'The connection to your phone was lost and this page was cleared. Please connect again.',
  conflicts: n => `${n} changed on both devices, and both versions were kept: the other one has "Conflict copy" in its title.`,
};

const ADDRESS_KEY = 'passby-sync-address';
const IDLE_MS = 5 * 60 * 1000;
const UNTOUCHED_MS = 10 * 60 * 1000;
const main = document.getElementById('main');
const disconnectButton = document.getElementById('disconnect');

// Builds an element. Text only ever arrives through textContent.
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [name, value] of Object.entries(props)) {
    if (name === 'text') node.textContent = value;
    else if (name === 'class') node.className = value;
    else if (name.startsWith('on')) node.addEventListener(name.slice(2), value);
    else if (value === true) node.setAttribute(name, '');
    else if (value !== false && value != null) node.setAttribute(name, value);
  }
  node.append(...children.filter(child => child != null));
  return node;
}

const stored = {
  get() { try { return localStorage.getItem(ADDRESS_KEY) || ''; } catch { return ''; } },
  set(value) { try { localStorage.setItem(ADDRESS_KEY, value); } catch { /* Private windows may refuse. */ } },
};

// ---- Connection ----

let session = null;
let pinned = null; // The one origin this page may connect to, once the policy below is in place.
let book = { entries: [], folders: [], tombstones: [] };
let view = { filter: '', query: '', selected: null, editing: null, revealed: false, busy: false, message: '', notice: '' };

// Narrows the page's own policy to the one phone before any key is derived. Policies only ever
// combine to something stricter, so from here on this page cannot connect anywhere else.
function pin(origin) {
  document.head.append(el('meta', { 'http-equiv': 'Content-Security-Policy', content: `connect-src ${origin}` }));
  pinned = origin;
}

async function post(path, body) {
  const response = await fetch(pinned + path, {
    method: 'POST', body, mode: 'cors', credentials: 'omit', cache: 'no-store', redirect: 'error',
    referrerPolicy: 'no-referrer', targetAddressSpace: 'local',
    // The first request is the one the browser may hold while it asks to access the local network.
    signal: AbortSignal.timeout(path.endsWith('/begin') ? 90000 : 20000),
  });
  return { status: response.status, body: new Uint8Array(await response.arrayBuffer()) };
}

async function localNetworkState() {
  for (const name of ['local-network', 'local-network-access']) {
    try { return (await navigator.permissions.query({ name })).state; } catch { /* Try the older name. */ }
  }
  return 'unsupported';
}

async function connect(addressText, codeText, report) {
  const address = privateAddress(addressText);
  const code = canonicalCode(codeText);
  if (!address) return report(T.badAddress);
  if (!code) return report(T.badCode);
  const text = `${address.host}:${address.port}`;
  const origin = `http://${text}`;
  if (pinned && pinned !== origin) {
    // The policy cannot be widened; another phone means a fresh page.
    location.hash = text;
    location.reload();
    return;
  }
  if (!pinned) pin(origin);
  report('', true);
  const next = new Session(post);
  try {
    await next.start(code);
    const result = await next.exchange({ entries: [], folders: [], tombstones: [] });
    session = next;
    book = result.state;
    stored.set(text);
    view = { ...view, selected: null, editing: null, message: '', notice: T.connected(text) };
    renderBook();
  } catch (e) {
    next.close();
    const denied = e.kind === 'unreachable' && await localNetworkState() === 'denied';
    report(denied ? T.denied : T.errors[e.kind] || T.errors.failed);
  }
}

// Clears everything this page holds by loading it afresh. The address stays in the link.
function clear() {
  session?.close();
  location.reload();
}

let hiddenAt = null;
let idleTimer = null;
document.addEventListener('visibilitychange', () => {
  if (!session) return;
  if (document.hidden) {
    hiddenAt = Date.now();
    idleTimer = setTimeout(clear, IDLE_MS);
  } else {
    clearTimeout(idleTimer);
    if (hiddenAt !== null && Date.now() - hiddenAt >= IDLE_MS) clear();
    hiddenAt = null;
  }
});

// A page left open in front is cleared too, once nobody has touched it for ten minutes.
let touchedAt = Date.now();
for (const type of ['keydown', 'pointerdown', 'pointermove', 'wheel', 'touchstart']) {
  document.addEventListener(type, () => { touchedAt = Date.now(); }, { passive: true, capture: true });
}
setInterval(() => { if (session && Date.now() - touchedAt >= UNTOUCHED_MS) clear(); }, 15000);

// Sends the page's whole state and takes the phone's merged answer. The page changes nothing by
// itself: what is shown is always what the phone confirmed.
async function sync(next) {
  view.busy = true;
  view.message = T.saving;
  renderBook();
  try {
    const result = await session.exchange(next);
    book = result.state;
    view.busy = false;
    view.message = result.summary && result.summary.conflicts > 0 ? T.conflicts(result.summary.conflicts) : '';
    return true;
  } catch (e) {
    view.busy = false;
    if (e.kind === 'wrongCode' || e.kind === 'stopped' || e.kind === 'untrusted') {
      // The session is over; nothing more can be saved through it.
      session.close();
      session = null;
      book = { entries: [], folders: [], tombstones: [] };
      renderConnect(T.lost);
      return false;
    }
    view.message = T.notSaved + (T.errors[e.kind] || T.errors.failed);
    return false;
  }
}

// ---- Connect page ----

async function renderConnect(message = '') {
  disconnectButton.hidden = true;
  // The address may arrive after the # of a link shared from the phone. Anything else there is ignored.
  let fromLink = null;
  try { fromLink = privateAddress(decodeURIComponent(location.hash.slice(1))); } catch { /* Not an address. */ }
  const address = el('input', { id: 'address', class: 'mono', inputmode: 'decimal', autocomplete: 'off', spellcheck: 'false', placeholder: '192.168.1.20:52814',
    value: fromLink ? `${fromLink.host}:${fromLink.port}` : stored.get() });
  const code = el('input', { id: 'code', class: 'mono', autocomplete: 'off', autocapitalize: 'characters', spellcheck: 'false', placeholder: 'XXXX-XXXX-XXXX', maxlength: '20' });
  const status = el('p', { class: 'error', role: 'status', text: message });
  const button = el('button', { class: 'primary', type: 'submit', text: T.connect });
  const form = el('form', { class: 'narrow', onsubmit: event => {
    event.preventDefault();
    const typed = code.value;
    code.value = '';
    connect(address.value, typed, (text, working = false) => {
      status.textContent = text;
      button.disabled = working;
      button.textContent = working ? T.connecting : T.connect;
    });
  } },
  el('label', { for: 'address', text: T.address }), address,
  el('label', { for: 'code', text: T.code }), code,
  el('div', { class: 'actions' }, button), status);
  const support = el('p', { class: 'note' });
  main.replaceChildren(el('h1', { text: T.title }), el('p', { class: 'note narrow', text: T.intro }),
    el('ol', { class: 'narrow' }, ...T.steps.map(text => el('li', { text }))), support, form,
    el('p', { class: 'hint narrow' }, el('a', { href: '/privacy/', text: T.privacy }), ' · ', el('a', { href: '/terms/', text: T.terms })));
  (address.value ? code : address).focus();
  const state = await localNetworkState();
  if (state === 'unsupported') support.textContent = T.browser;
  else if (state === 'denied') support.textContent = T.denied;
}

// ---- Notebook ----

const titleOf = entry => entry.title.trim() || T.untitled;
const folderName = id => book.folders.find(f => f.id === id)?.name;

function shown() {
  const q = view.query.trim().toLowerCase();
  return book.entries
    .filter(e => view.filter === '' || (view.filter === 'unfiled' ? !e.folderID : e.folderID === view.filter))
    .filter(e => !q || e.title.toLowerCase().includes(q) || e.account.toLowerCase().includes(q) || e.notes.toLowerCase().includes(q))
    .sort((a, b) => titleOf(a).localeCompare(titleOf(b)));
}

function select(id) {
  view = { ...view, selected: id, editing: null, revealed: false, message: '' };
  renderBook();
}

async function save(draft) {
  const entry = { id: draft.id, title: draft.title, account: draft.account, password: draft.password, notes: draft.notes, updatedAt: Date.now(), dirty: true };
  if (draft.folderID) entry.folderID = draft.folderID;
  const next = { ...book, entries: [...book.entries.filter(e => e.id !== entry.id), entry] };
  if (await sync(next)) view = { ...view, selected: book.entries.some(e => e.id === entry.id) ? entry.id : null, editing: null, revealed: false };
  if (session) renderBook();
}

async function remove(entry) {
  if (!confirm(T.confirmRemove(titleOf(entry)))) return;
  const next = { ...book, entries: book.entries.filter(e => e.id !== entry.id),
    tombstones: [...book.tombstones.filter(t => !(t.kind === 'entry' && t.id === entry.id)), { id: entry.id, kind: 'entry', deletedAt: Date.now(), dirty: true }] };
  if (await sync(next)) view = { ...view, selected: null, editing: null };
  if (session) renderBook();
}

async function copy(text, button) {
  try {
    await navigator.clipboard.writeText(text);
    button.textContent = T.copied;
    setTimeout(() => { button.textContent = T.copy; }, 1500);
  } catch { /* The browser refused; nothing was copied. */ }
}

function field(name, value, ...buttons) {
  return el('div', { class: 'field' }, el('div', { class: 'name', text: name }),
    el('div', { class: 'row' }, el('div', { class: 'value', text: value }), ...buttons));
}

function detail(entry) {
  const copyButton = text => { const b = el('button', { type: 'button', text: T.copy, onclick: () => copy(text, b) }); return b; };
  const password = el('div', { class: 'value mono', text: view.revealed ? entry.password : '•'.repeat(Math.min(entry.password.length, 12)) });
  return el('section', {}, el('h2', { text: titleOf(entry) }),
    field(T.fAccount, entry.account || T.noAccount, entry.account ? copyButton(entry.account) : null),
    el('div', { class: 'field' }, el('div', { class: 'name', text: T.fPassword }), el('div', { class: 'row' }, password,
      el('button', { type: 'button', text: view.revealed ? T.hide : T.show, onclick: () => { view.revealed = !view.revealed; renderBook(); } }),
      entry.password ? copyButton(entry.password) : null)),
    entry.notes ? field(T.fNotes, entry.notes) : null,
    entry.folderID && folderName(entry.folderID) ? field(T.fFolder, folderName(entry.folderID)) : null,
    el('p', { class: 'hint', text: T.clipboard }),
    el('div', { class: 'actions' },
      el('button', { class: 'primary', type: 'button', text: T.edit, disabled: view.busy, onclick: () => { view.editing = { ...entry }; renderBook(); } }),
      el('button', { type: 'button', text: T.remove, disabled: view.busy, onclick: () => remove(entry) })));
}

function editor(draft) {
  const input = (key, props = {}) => el('input', { id: 'f-' + key, value: draft[key], autocomplete: 'off', spellcheck: 'false', oninput: e => { draft[key] = e.target.value; }, ...props });
  const notes = el('textarea', { id: 'f-notes', oninput: e => { draft.notes = e.target.value; } });
  notes.value = draft.notes;
  const folder = el('select', { id: 'f-folder', onchange: e => { draft.folderID = e.target.value || undefined; } },
    el('option', { value: '', text: T.unfiled }), ...book.folders.map(f => el('option', { value: f.id, text: f.name, selected: f.id === draft.folderID })));
  return el('form', { onsubmit: e => { e.preventDefault(); save(draft); } },
    el('label', { for: 'f-title', text: T.fTitle }), input('title'),
    el('label', { for: 'f-account', text: T.fAccount }), input('account'),
    el('label', { for: 'f-password', text: T.fPassword }), input('password', { class: 'mono' }),
    el('label', { for: 'f-notes', text: T.fNotes }), notes,
    el('label', { for: 'f-folder', text: T.fFolder }), folder,
    el('div', { class: 'actions' },
      el('button', { class: 'primary', type: 'submit', text: T.save, disabled: view.busy }),
      el('button', { type: 'button', text: T.cancel, disabled: view.busy, onclick: () => { view.editing = null; renderBook(); } })));
}

function renderBook() {
  disconnectButton.hidden = false;
  disconnectButton.textContent = T.disconnect;
  const entries = shown();
  const chip = (label, value) => el('button', { type: 'button', text: label, 'aria-pressed': String(view.filter === value), onclick: () => { view.filter = value; renderBook(); } });
  const searching = document.activeElement?.type === 'search';
  const search = el('input', { type: 'search', placeholder: T.search, 'aria-label': T.search, value: view.query,
    oninput: e => { view.query = e.target.value; renderBook(); } });
  const list = el('ul', { class: 'list' }, ...entries.map(e => el('li', {}, el('button', { type: 'button', 'aria-current': String(e.id === view.selected), onclick: () => select(e.id) },
    el('span', { class: 'title', text: titleOf(e) }), el('span', { class: 'account', text: e.account || T.noAccount })))));
  const current = book.entries.find(e => e.id === view.selected);
  const right = view.editing ? editor(view.editing) : current ? detail(current) : el('p', { class: 'note', text: T.pick });
  main.replaceChildren(
    el('p', { class: 'status', role: 'status', text: view.message || view.notice }),
    el('div', { class: 'columns' },
      el('div', {},
        el('div', { class: 'toolbar' }, search),
        el('div', { class: 'chips' }, chip(T.all, ''), book.entries.some(e => !e.folderID) && book.folders.length ? chip(T.unfiled, 'unfiled') : null, ...book.folders.map(f => chip(f.name, f.id))),
        entries.length ? list : el('p', { class: 'note', text: book.entries.length ? T.noMatch : T.empty }),
        el('div', { class: 'actions' },
          el('button', { class: 'primary', type: 'button', text: T.add, disabled: view.busy, onclick: () => {
            view.editing = { id: crypto.randomUUID().toUpperCase(), title: '', account: '', password: '', notes: '', folderID: book.folders.some(f => f.id === view.filter) ? view.filter : undefined };
            view.selected = null;
            renderBook();
          } }),
          el('button', { type: 'button', text: T.refresh, disabled: view.busy, onclick: async () => { await sync(book); if (session) renderBook(); } }))),
      right));
  if (searching) {
    search.focus();
    search.setSelectionRange(view.query.length, view.query.length);
  }
}

disconnectButton.addEventListener('click', clear);
renderConnect();
