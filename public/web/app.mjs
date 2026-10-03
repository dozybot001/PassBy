import { CloudNotebook } from './cloud.mjs';
import { NotebookSession } from './session.mjs';
import { generatePassword } from './crypto.mjs';
import { newID } from './model.mjs';
import { TrustedBrowser, bindingID } from './trusted-browser.mjs';

const copy = {
  en: {
    security:'Encrypted on your device. Linked to your Apple Account.', signIn:'Open your notebook', signInHelp:'Sign in to the Apple Account you use with PassBy on iPhone.',
    unlock:'Unlock notebook', key:'Recovery key', keyPlaceholder:'Paste your recovery key', keyHelp:'Your recovery key and passwords stay in this page’s memory. Leaving the window locks your notebook.',
    connect:'Continue with Apple', connecting:'Connecting…', lock:'Lock notebook', locked:'Notebook locked', settings:'Settings', search:'Search', generator:'Password generator', privacy:'Privacy', support:'Support',
    all:'All', unfiled:'Unfiled', newPassword:'New password', newFolder:'New folder', folders:'Folders', empty:'Your notebook starts here', emptyHelp:'Add an account and password. Keep the details in one place.', noResults:'No matching entries', noResultsHelp:'Try another title or account.', choose:'A little space for your passwords.', chooseHelp:'Choose an entry to see its details.', placeholder:'Search titles or accounts', edit:'Edit', save:'Save', saving:'Saving…', cancel:'Cancel', close:'Close', back:'Back', account:'Account', password:'Password', title:'Title', notes:'Notes', folder:'Folder', noNotes:'No notes added', copy:'Copy', copied:'Copied', show:'Show password', hide:'Hide password', delete:'Delete entry', deleteConfirm:'Delete this entry?', deleteHelp:'It will be removed from your notebook. This cannot be undone.', deleteFolder:'Delete folder', deleteFolderHelp:'Its passwords will move to Unfiled. This cannot be undone.', confirm:'Delete', saved:'Notebook synced', refreshed:'Notebook refreshed', refresh:'Sync now', conflictCopy:' (Conflict copy)', conflicts:'Concurrent changes were kept as conflict copies.', length:'Length', upper:'Uppercase letters', lower:'Lowercase letters', digits:'Numbers', symbols:'Symbols', another:'Generate another', use:'Use & copy', copyPassword:'Copy password', lengthHelp:'Choose 8–24 with the slider, or enter up to 4096 characters.', clipboardHelp:'Copied passwords follow your browser and operating system’s clipboard rules. They are not automatically cleared.', language:'Language', automaticLock:'Automatic lock', automaticLockHelp:'Switching tabs, leaving the window or 5 minutes without activity locks this notebook.', browserHelp:'The web app cannot use iPhone Face ID or block screenshots. Unlock again with your recovery key.', discard:'Discard changes?', discardHelp:'This unfinished entry has not been saved.', discardButton:'Discard', continueEditing:'Keep editing', required:'Enter a title and password.', folderName:'Folder name', signedOut:'Signed out', existingHelp:'Create your notebook in PassBy on iPhone first, then wait for iCloud sync.',
    invalidKey:'Check the recovery key. Its length or checksum is incorrect.', wrongKey:'This recovery key does not unlock your notebook.', invalidNotebook:'The notebook could not be verified. Your iCloud data has not been changed.', version:'This notebook uses an unsupported format. Update PassBy.', service:'Unable to sync your notebook. Please try again.', noNotebook:'No notebook found in this iCloud account. Create one in PassBy on iPhone and let it sync first.', notConfigured:'Web access is being configured. Your iPhone notebook is unchanged.', invalidLength:'Choose a whole number from 8 to 4096.', selectCharacters:'Select at least one character type.', conflict:'The notebook changed again. Please try saving again.', clipboard:'Copy was blocked by the browser. Select the value and copy it manually.', lockedError:'Unlock your notebook again.', generic:'Something went wrong. Please try again.',
  },
  zh: {
    security:'设备端加密，绑定你的 Apple 账号。',signIn:'打开密码本',signInHelp:'登录你在 iPhone PassBy 中使用的 Apple 账号。',unlock:'解锁密码本',key:'恢复密钥',keyPlaceholder:'粘贴恢复密钥',keyHelp:'恢复密钥和密码只留在当前页面内存中。离开窗口后，密码本会锁定。',connect:'通过 Apple 继续',connecting:'连接中…',lock:'锁定密码本',locked:'密码本已锁定',settings:'设置',search:'搜索',generator:'密码生成器',privacy:'隐私',support:'支持',all:'全部',unfiled:'未分类',newPassword:'新建密码',newFolder:'新建文件夹',folders:'文件夹',empty:'密码本从这里开始',emptyHelp:'添加账号和密码，将细节保存在一起。',noResults:'没有匹配的条目',noResultsHelp:'试试其他标题或账号。',choose:'为你的密码，留一个位置。',chooseHelp:'选择条目，查看它的详细内容。',placeholder:'搜索标题或账号',edit:'编辑',save:'保存',saving:'保存中…',cancel:'取消',close:'关闭',back:'返回',account:'账号',password:'密码',title:'标题',notes:'备注',folder:'文件夹',noNotes:'没有备注',copy:'复制',copied:'已复制',show:'显示密码',hide:'隐藏密码',delete:'删除条目',deleteConfirm:'删除这个条目？',deleteHelp:'将从密码本中删除，无法撤销。',deleteFolder:'删除文件夹',deleteFolderHelp:'其中的密码将移至未分类，无法撤销。',confirm:'删除',saved:'密码本已同步',refreshed:'密码本已刷新',refresh:'立即同步',conflictCopy:'（冲突副本）',conflicts:'同时修改的内容已保留为冲突副本。',length:'长度',upper:'大写字母',lower:'小写字母',digits:'数字',symbols:'符号',another:'再生成一个',use:'使用并复制',copyPassword:'复制密码',lengthHelp:'滑块可选 8～24 位，也可手动输入最多 4096 位。',clipboardHelp:'已复制的密码遵循浏览器与系统的剪贴板规则，不会自动清除。',language:'语言',automaticLock:'自动锁定',automaticLockHelp:'切换标签页、离开窗口或 5 分钟无操作后，密码本会锁定。',browserHelp:'网页无法使用 iPhone 的 Face ID 或阻止截图，请用恢复密钥重新解锁。',discard:'放弃修改？',discardHelp:'这个未完成的条目尚未保存。',discardButton:'放弃',continueEditing:'继续编辑',required:'请填写标题和密码。',folderName:'文件夹名称',signedOut:'已退出登录',existingHelp:'请先在 iPhone PassBy 创建密码本，并等待 iCloud 同步。',invalidKey:'恢复密钥的长度或校验码不正确，请检查。',wrongKey:'此恢复密钥无法解锁这个密码本。',invalidNotebook:'无法验证密码本，iCloud 数据未被更改。',version:'密码本格式不受支持，请更新 PassBy。',service:'无法同步密码本，请重试。',noNotebook:'当前 iCloud 账号没有密码本，请先在 iPhone 创建并完成同步。',notConfigured:'网页版访问正在配置中，iPhone 密码本不受影响。',invalidLength:'请输入 8～4096 之间的整数。',selectCharacters:'至少选择一种字符类型。',conflict:'密码本又被修改了，请重试保存。',clipboard:'浏览器阻止了复制，请选中内容手动复制。',lockedError:'请重新解锁密码本。',generic:'操作未完成，请重试。',
  },
};
let language = navigator.language.startsWith('zh') ? 'zh' : 'en';
Object.assign(copy.en, {
  connected:'Apple Account connected', connect:'Continue with Apple', checking:'Checking your notebook…',
  remember:'Keep Apple signed in on this trusted computer', rememberHelp:'Optional. Your recovery key is still required every time you unlock.',
  keyHelp:'Your recovery key and passwords stay in this page’s memory. Leaving the window locks your notebook.',
  switchAccount:'Change Apple Account', retry:'Try again', missingTitle:'Your notebook is not available on the web yet',
  missingHelp:'On your iPhone, update PassBy and finish syncing your notebook. If Settings offers “Enable web access”, choose it, then check again here.',
  noNotebook:'Your notebook is not available on the web yet. Finish syncing in PassBy on iPhone, then try again.',
  security:'Encrypted on your device. Linked to your Apple Account.',
});
Object.assign(copy.zh, {
  connected:'Apple 账号已连接', connect:'通过 Apple 继续', checking:'正在检查密码本…',
  remember:'在这台可信电脑上保持 Apple 登录', rememberHelp:'可选。每次解锁仍需输入恢复密钥。',
  keyHelp:'恢复密钥和密码只留在当前页面内存中。离开窗口后，密码本会锁定。',
  switchAccount:'更换 Apple 账号', retry:'重试', missingTitle:'密码本尚未同步至网页版',
  missingHelp:'请在 iPhone 更新 PassBy，并完成密码本同步。如果设置中出现“启用网页访问”，请点选，然后在这里重新检查。',
  noNotebook:'密码本尚未同步至网页版，请在 iPhone PassBy 完成同步后重试。',
  security:'设备端加密，绑定你的 Apple 账号。',
});
copy.en.browserStorage='Browser authorization could not be saved or removed. Check browser storage permissions and try again.';
copy.zh.browserStorage='无法保存或撤销浏览器授权，请检查浏览器存储权限后重试。';
copy.en.keyHelp='Passwords remain in page memory. This authorized browser stores a non-exportable decryption key.';
copy.zh.keyHelp='密码只在页面内存中。这台已授权浏览器保存不可导出的解密密钥。';
const t = key => copy[language][key] || copy.en[key] || key;
const $ = id => document.getElementById(id);
const main = $('main'), tools = $('tools'), dialog = $('dialog');
const session = new NotebookSession(new CloudNotebook());
const trustedBrowser = new TrustedBrowser();
let trustedKey = null, trustBinding = null;
function validTenon(){return tenonIdentity && tenonIdentity.expires>Date.now();}
function currentBinding(){return validTenon()?bindingID(tenonIdentity,session.cloud.userRecordName):null;}
const authIn = document.createElement('div'), authOut = document.createElement('div');
authIn.id = 'apple-sign-in-button'; authOut.id = 'apple-sign-out-button';
authIn.className = 'auth-holder'; authOut.className = 'auth-holder account-switch';
let signedIn = false, connecting = true, filter = 'all', selected = null, query = '', searchOpen = false, revealed = false;
let authError = null, notebookState = 'checking', notebookError = null, notebookGeneration = 0, authenticationGeneration = 0;
let rememberApple = false;
let tenonIdentity = null, tenonLoading = true, tenonError = false, tenonExpiry, tenonSigningOut = false;
const tenonCallbackFailed = new URLSearchParams(location.search).has('auth_error');
try { rememberApple = localStorage.getItem('passby.rememberApple') === 'true'; } catch {}
let editor = null, dialogKind = null, generatorValue = '', idleTimer, statusTimer;
let busyOperations = 0, deletion = null;
const busyControls = new WeakMap();
const paths = {
  search:'<circle cx="10.5" cy="10.5" r="6.5"/><path d="m16 16 5 5"/>',
  generator:'<rect x="3" y="3" width="18" height="18" rx="5"/><circle cx="8" cy="8" r=".7"/><circle cx="16" cy="8" r=".7"/><circle cx="12" cy="12" r=".7"/><circle cx="8" cy="16" r=".7"/><circle cx="16" cy="16" r=".7"/>',
  settings:'<path d="M4 6h7m5 0h4M4 12h2m5 0h9M4 18h10m5 0h1"/><circle cx="13.5" cy="6" r="2.5"/><circle cx="8.5" cy="12" r="2.5"/><circle cx="16.5" cy="18" r="2.5"/>',
  lock:'<rect x="5" y="10" width="14" height="11" rx="3"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/>',
  copy:'<rect x="8" y="7" width="12" height="14" rx="2"/><path d="M16 7V5a2 2 0 0 0-2-2H6a2 2 0 0 0-2 2v10a2 2 0 0 0 2 2h2"/>',
  show:'<path d="M2 12s4-7 10-7 10 7 10 7-4 7-10 7S2 12 2 12Z"/><circle cx="12" cy="12" r="3"/>',
  hide:'<path d="m3 3 18 18M10 5c7-1 12 7 12 7s-1 2-3 3M6 6c-3 2-4 6-4 6s4 7 10 7c2 0 4-1 5-2"/>',
  plus:'<path d="M12 5v14M5 12h14"/>', folder:'<path d="M3 7a2 2 0 0 1 2-2h5l2 2h7a2 2 0 0 1 2 2v10a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2Z"/>',
  close:'<path d="m6 6 12 12M6 18 18 6"/>', back:'<path d="m15 5-7 7 7 7"/>',
  delete:'<path d="M4 6h16M9 6V3h6v3M6 6l1 15h10l1-15M10 10v7M14 10v7"/>',
  notebook:'<rect x="5" y="3" width="14" height="18" rx="3"/><path d="M9 8h6M9 12h6M9 16h3"/>',
};
function icon(name) { const span = document.createElement('span'); span.innerHTML = `<svg viewBox="0 0 24 24" aria-hidden="true">${paths[name] || paths.notebook}</svg>`; return span.firstElementChild; }
function node(tag, className, text) { const el = document.createElement(tag); if (className) el.className = className; if (text !== undefined) el.textContent = text; return el; }
function button(label, action, className='pill', symbol) {
  const el = node('button', className); el.type='button'; el.setAttribute('aria-label', label); el.title=label;
  if (symbol) el.append(icon(symbol)); if (className !== 'icon-button' && !className.includes('icon-button')) el.append(document.createTextNode(label));
  el.addEventListener('click', event => {
    if (el.disabled || el.hasAttribute('aria-busy')) return;
    if(session.key && !validTenon()){tenonIdentity=null;lock();return;}
    const result = action(event);
    if (result?.then) {
      el.disabled = true; el.setAttribute('aria-busy','true'); el.classList.add('is-loading');
      busyOperations++;$('language').disabled=true;
      void result.catch(()=>notify(t('generic'))).finally(() => { busyOperations--; $('language').disabled=busyOperations>0; el.disabled = false; el.removeAttribute('aria-busy'); el.classList.remove('is-loading'); });
    }
  }); return el;
}
function notify(message) { clearTimeout(statusTimer); $('status').textContent=message; $('status').hidden=false; statusTimer=setTimeout(() => { $('status').hidden=true; $('status').textContent=''; },5000); }
function errorMessage(error) { return t(error?.code === 'locked' ? 'lockedError' : error?.code || 'generic'); }
function showError(parent, error) { parent.querySelector('.error')?.remove(); const el=node('p','error',errorMessage(error)); el.setAttribute('role','alert'); parent.append(el); }
function setBusy(parent, busy) {
  if (busy && !busyControls.has(parent)) {
    const controls = [...parent.querySelectorAll('button,input,textarea,select')].map(el => [el,el.disabled]);
    const submit = parent.querySelector('button[type=submit]') || (parent.contains(document.activeElement) && document.activeElement?.closest('button')) || parent.querySelector('.primary');
    busyControls.set(parent,{controls,submit}); busyOperations++;
    controls.forEach(([el])=>el.disabled=true);
    if(submit){submit.classList.add('is-loading');submit.setAttribute('aria-busy','true');}
  } else if (!busy && busyControls.has(parent)) {
    const {controls,submit}=busyControls.get(parent);busyControls.delete(parent);busyOperations--;
    controls.forEach(([el,disabled])=>el.disabled=disabled);
    if(submit){submit.classList.remove('is-loading');submit.removeAttribute('aria-busy');}
  }
  $('language').disabled=busyOperations>0;
  const select=$('app-language');if(select)select.disabled=busyOperations>0;
}
function closeDialog() { dialog.close(); dialog.replaceChildren(); dialogKind=null; generatorValue=''; deletion=null; }
function lock() {
  if(!validTenon()){trustedKey=null;trustBinding=null;}
  const hadSecrets = !!session.key || !!editor || !!generatorValue;
  session.lock(); editor=null; revealed=false; selected=null; query=''; searchOpen=false;
  closeDialog(); clearTimeout(idleTimer); $('status').hidden=true; $('status').textContent='';
  // Clear the recovery field even when it is awaiting an asynchronous request.
  main.querySelectorAll('input,textarea').forEach(e => e.value='');
  render(); if (hadSecrets) notify(t('locked'));
}
function resetIdle() { clearTimeout(idleTimer); if (session.key) idleTimer=setTimeout(lock,300000); }
document.addEventListener('visibilitychange',()=>{ if(document.hidden) lock(); });
window.addEventListener('blur',()=>{ if(session.key || editor || generatorValue || main.querySelector('#recovery-key')?.value) lock(); });
window.addEventListener('pagehide',lock);
window.addEventListener('pageshow',event=>{ if(event.persisted) lock(); });
for(const event of ['pointerdown','keydown','submit'])document.addEventListener(event,e=>{
  if(tenonIdentity && !validTenon()){tenonIdentity=null;lock();e.preventDefault();e.stopImmediatePropagation();}
},{capture:true});
window.addEventListener('focus',()=>{if(tenonIdentity && !validTenon()){tenonIdentity=null;lock();}});
for (const event of ['pointerdown','keydown','input']) document.addEventListener(event,resetIdle,{passive:true});
document.addEventListener('keydown',event=>{ if(event.key==='Escape' && session.key && !dialog.open && !searchOpen) lock(); });
dialog.addEventListener('cancel',event=>{ if(editor){event.preventDefault();if(dialogKind==='editor'||dialogKind==='discard')cancelEditor();else renderEditor();}else closeDialog(); });
function render() {
  document.querySelector('.app').classList.toggle('entry-mode',!session.key);
  document.documentElement.lang=language==='zh'?'zh-Hans':'en';
  document.querySelector('.header .wordmark').setAttribute('aria-label',language==='zh'?'PassBy，Tenon 出品，首页':'PassBy, by Tenon, home');
  $('privacy-link').textContent=t('privacy'); $('support-link').textContent=t('support'); $('language').textContent=language==='zh'?'English':'简体中文';
  tools.replaceChildren(button(t('generator'),()=>openGenerator(),'icon-button','generator'),button(t('settings'),openSettings,'icon-button','settings'));
  if(session.key) tools.prepend(button(t('search'),()=>{searchOpen=!searchOpen;renderWorkspace(); if(searchOpen) $('search-input')?.focus();},'icon-button','search'));
  if(session.key) tools.append(button(t('lock'),lock,'icon-button desktop-only','lock'));
  if(session.key) renderWorkspace(); else renderWelcome();
}
function changeLanguage(value) {
  if(busyOperations || value===language)return;
  const previous=language, kind=dialogKind;
  const keyInput=$('recovery-key')?.value || '';
  const folderName=$('field-folderName')?.value || '';
  const generator = kind==='generator' ? {
    length:$('password-length').value,
    characters:Object.fromEntries(['upper','lower','digits','symbols'].map(k=>[k,$(`generator-${k}`).checked])),
    value:generatorValue, fromEditor:!!editor,
  } : null;
  const pendingDelete=deletion;
  language=value;closeDialog();render();
  if(kind==='editor')renderEditor();
  else if(kind==='generator')openGenerator(generator.fromEditor,generator);
  else if(kind==='newFolder'){openNewFolder(!!editor);$('field-folderName').value=folderName;}
  else if(kind==='folders')openFolders();
  else if(kind==='discard')cancelEditor();
  else if(kind==='about')openAbout();
  else if(kind==='settings')openSettings();
  else if(kind==='confirm' && pendingDelete){
    const translate=text=>{const key=Object.keys(copy[previous]).find(k=>copy[previous][k]===text);return key?t(key):text;};
    confirmDelete(translate(pendingDelete.title),translate(pendingDelete.message),pendingDelete.action);
  }
  if(keyInput && $('recovery-key'))$('recovery-key').value=keyInput;
  if(tenonIdentity && !signedIn) { authIn.replaceChildren();authOut.replaceChildren();void prepareApple(); }
}
$('language').addEventListener('click',()=>changeLanguage(language==='zh'?'en':'zh'));
function decorateAuthButtons() {
  for (const [holder, label] of [[authIn, t('connect')], [authOut, t('switchAccount')]]) {
    const element = holder.querySelector('.apple-auth-button');
    if (!element) continue;
    element.setAttribute('role', 'button'); element.setAttribute('aria-label', label); element.tabIndex = 0;
    // CloudKit JS v2's bundled button art is English-only. Keep Apple's
    // element and gesture handler, and localize only its visible label.
    let text = element.querySelector('.auth-button-label');
    if (!text) { text = node('span', 'auth-button-label'); element.append(text); }
    text.textContent = label;
    element.onkeydown = event => { if (event.key === 'Enter' || event.key === ' ') { event.preventDefault(); element.click(); } };
  }
}
async function checkNotebook() {
  const generation = ++notebookGeneration;
  notebookState = 'checking'; notebookError = null; render();
  try {
    await session.cloud.fetchRecord();
    if (!signedIn || generation !== notebookGeneration) return;
    const binding=currentBinding();
    const cached=binding ? await trustedBrowser.get(binding).catch(()=>null) : null;
    if(!signedIn || generation!==notebookGeneration || !validTenon())return;
    trustBinding=binding;trustedKey=cached;
    notebookState = 'available';
    if(trustedKey && document.hasFocus() && !document.hidden){
      const binding=trustBinding;await session.unlockWithKey(trustedKey);
      if(!validTenon() || binding!==currentBinding() || generation!==notebookGeneration || document.hidden || !document.hasFocus()){lock();return;}
      selected=null;resetIdle();
    }
  } catch (error) {
    if (!signedIn || generation !== notebookGeneration) return;
    if(error.code==='wrongKey' && trustBinding){await trustedBrowser.forget(trustBinding).catch(()=>{});trustedKey=null;notebookState='available';}
    else {notebookState = error.code === 'noNotebook' ? 'missing' : 'failed'; notebookError = error;}
  }
  render();
}
async function prepareApple() {
  const generation = ++authenticationGeneration;
  connecting = true; authError = null; render();
  try {
    await session.cloud.authenticate(() => {
      if (generation !== authenticationGeneration) return;
      signedIn = true; connecting = false; lock(); void checkNotebook();
    }, () => {
      if (generation !== authenticationGeneration) return;
      signedIn = false; ++notebookGeneration; notebookState = 'checking'; lock(); notify(t('signedOut'));
    }, language, { remember: rememberApple, theme: matchMedia('(prefers-color-scheme: dark)').matches ? 'white' : 'black',
      onError: error => { if (generation === authenticationGeneration) { authError = error; signedIn = false; ++notebookGeneration; lock(); } },
    });
  } catch (error) { if (generation === authenticationGeneration) authError = error; }
  finally { if (generation === authenticationGeneration) { connecting = false; render(); } }
}
function renderWelcome() {
  const welcome = node('section', 'welcome'), card = node('section', 'unlock-card');
  if (!tenonIdentity) {
    card.classList.add('tenon-entry');
    card.append(node('h1','',language==='zh'?'登录 PassBy':'Sign in to PassBy'),
      node('p','',language==='zh'?'使用 Tenon 账号，统一管理你的登录方式。':'Use your Tenon Account to manage your sign-in methods.'));
    if (tenonLoading) {
      const pending=button(t('connecting'),()=>{},'pill primary');pending.disabled=true;pending.classList.add('is-loading');pending.setAttribute('aria-busy','true');card.append(pending);
    }
    else {
      if (tenonError) { const error=node('p','',language==='zh'?'账号服务暂时不可用，请重试。':'Account service unavailable. Please try again.');error.setAttribute('role','alert');card.append(error); }
      const actions=node('div','tenon-actions');
      const login=node('a','pill primary',language==='zh'?'使用 Tenon 账号登录':'Sign in with Tenon');login.href='./api/auth/start';login.addEventListener('click',event=>{
        if(login.getAttribute('aria-busy')==='true'){event.preventDefault();return;}
        login.setAttribute('aria-busy','true');login.classList.add('is-loading');
      });actions.append(login);
      if(tenonError)actions.append(button(t('retry'),prepareTenon,'pill'));
      card.append(actions);
    }
    card.append(node('p','help',language==='zh'?'Tenon 管理登录身份。密码本仍由 Apple 私有云授权，恢复密钥只在本页解密。':'Tenon handles your identity. Apple authorizes private notebook storage; your recovery key decrypts it only on this page.'));
    welcome.append(card);main.replaceChildren(welcome);return;
  }
  const mark=node('img','access-mark');mark.src='./web/icon.svg';mark.alt='';
  if(tenonSigningOut){
    const loading=button(language==='zh'?'正在退出…':'Signing out…',()=>{},'pill primary');loading.disabled=true;loading.classList.add('is-loading');loading.setAttribute('aria-busy','true');
    card.append(mark,loading);welcome.append(card);main.replaceChildren(welcome);return;
  }
  card.append(mark, node('h1', '', t(signedIn ? 'unlock' : 'signIn')));
  card.append(node('p', signedIn ? 'connected' : '', t(signedIn ? 'connected' : 'signInHelp')));
  card.append(node('p','help',`${language==='zh'?'Tenon 账号：':'Tenon Account: '}${tenonIdentity.name}`));
  authIn.hidden = signedIn || connecting || !!authError; authOut.hidden = !signedIn;
  // Both mount points must exist before CloudKit setUpAuth runs. Reuse them
  // across renders so that Apple's listeners and popup gesture are preserved.
  card.append(authIn, authOut);
  if (signedIn) {
    if (notebookState === 'available') {
      if(trustedKey && trustBinding){
        card.append(node('p','help',language==='zh'?'这台浏览器已授权。无需再次输入恢复密钥。':'This browser is authorized. No recovery key is needed.'));
        const open=button(t('unlock'),async()=>{
          if(!validTenon()){tenonIdentity=null;lock();return;}
          const key=trustedKey,binding=currentBinding();setBusy(card,true);
          try{
            await session.unlockWithKey(key);
            if(!validTenon() || binding!==currentBinding() || document.hidden || !document.hasFocus()){lock();return;}
            selected=null;resetIdle();render();
          }catch(error){
            if(error.code==='wrongKey'){await trustedBrowser.forget(binding);trustedKey=null;render();}
            else if(error.code!=='locked')showError(card,error);
          }finally{setBusy(card,false);}
        },'pill primary');open.classList.add('trusted-open');card.append(open);
      }else{
        const form=node('form'),label=node('label','',t('key'));label.htmlFor='recovery-key';
        const input=node('input');input.id='recovery-key';input.type='password';input.autocomplete='off';input.spellcheck=false;input.placeholder=t('keyPlaceholder');input.required=true;
        const help=node('p','help',language==='zh'?'首次授权这台浏览器后，以后可在 Tenon 登录有效时直接打开。只保存不可导出的解密密钥，不保存恢复密钥原文。':'Authorize this browser once to open it during a valid Tenon session. Only a non-exportable decryption key is saved, never your recovery phrase.');
        const submit=node('button','pill primary',language==='zh'?'授权并打开密码本':'Authorize and open notebook');submit.type='submit';
        form.append(label,input,submit);form.addEventListener('submit',async event=>{
          event.preventDefault();if(!validTenon()){tenonIdentity=null;lock();return;}
          const text=input.value,binding=currentBinding();input.value='';setBusy(form,true);
          try{
            await session.unlock(text);
            if(!validTenon() || binding!==currentBinding() || document.hidden || !document.hasFocus()){lock();return;}
            await trustedBrowser.save(binding,session.key);
            if(!validTenon() || binding!==currentBinding() || !session.key){lock();return;}
            trustBinding=binding;trustedKey=session.key;selected=null;resetIdle();render();
          }catch(error){if(error.code==='browserStorage'){lock();notify(t('browserStorage'));}else if(error.code!=='locked')showError(form,error);}
          finally{setBusy(form,false);}
        });card.append(form,help);
      }
    } else {
      const state=node('div','access-state');state.setAttribute('aria-live','polite');
      if (notebookState === 'checking') {
        const pending=button(t('checking'),()=>{});pending.disabled=true;pending.classList.add('is-loading');pending.setAttribute('aria-busy','true');state.append(pending);
      }
      else {
        if (notebookState === 'missing') state.append(node('h2','',t('missingTitle')),node('p','',t('missingHelp')));
        else showError(state, notebookError);
        state.append(button(t('retry'),checkNotebook,'pill'));
      }
      card.append(state);
    }
    card.append(authOut);
  } else {
    if (connecting) { const loading=button(t('connecting'),()=>{},'pill primary');loading.disabled=true;loading.classList.add('is-loading');loading.setAttribute('aria-busy','true');card.append(loading); }
    if (authError) { showError(card,authError);card.append(button(t('retry'),prepareApple,'pill primary')); }
    const remember=node('label','remember-row'), check=node('input'), text=node('span','',t('remember'));
    check.type='checkbox';check.checked=rememberApple;check.disabled=connecting;remember.append(check,text);
    check.addEventListener('change',()=>{
      rememberApple=check.checked;
      try { if(rememberApple)localStorage.setItem('passby.rememberApple','true');else localStorage.removeItem('passby.rememberApple'); } catch {}
      authIn.replaceChildren();authOut.replaceChildren();void prepareApple();
    });
    card.append(remember,node('p','help remember-help',t('rememberHelp')));
  }
  const security=node('div','security-notes');security.append(icon('lock'),node('span','',t('security')));
  welcome.append(card,security);main.replaceChildren(welcome);decorateAuthButtons();
}
function filteredEntries() {return session.vault.entries.filter(e=>(filter==='all'||(filter==='unfiled'?!e.folderID:e.folderID===filter))&&(`${e.title} ${e.account}`).toLocaleLowerCase().includes(query.toLocaleLowerCase())).sort((a,b)=>a.title.localeCompare(b.title,language));}
function renderWorkspace() {
  if(!session.vault)return;
  const workspace=node('section',`workspace${selected?' has-detail':''}`),sidebar=node('aside','sidebar');
  if(searchOpen){const wrap=node('div','search-wrap'),input=node('input');input.id='search-input';input.type='search';input.placeholder=t('placeholder');input.setAttribute('aria-label',t('search'));input.value=query;input.autocomplete='off';input.addEventListener('input',()=>{query=input.value;renderList();});wrap.append(input);sidebar.append(wrap);}
  const filters=node('nav','filters');filters.setAttribute('aria-label',t('folders'));
  for(const f of [{id:'all',name:t('all')},{id:'unfiled',name:t('unfiled')},...session.vault.folders]){
    const btn=button(f.name,()=>{filter=f.id;renderWorkspace();},'filter');btn.setAttribute('aria-pressed',String(filter===f.id));btn.append(node('span','',String(session.vault.entries.filter(e=>f.id==='all'||(f.id==='unfiled'?!e.folderID:e.folderID===f.id)).length)));filters.append(btn);
  }sidebar.append(filters);const list=node('ul','entry-list');list.id='entries';sidebar.append(list);
  const actions=node('div','sidebar-actions');actions.append(button(t('folders'),openFolders,'icon-button','folder'),button(t('newPassword'),()=>openEditor(),'pill primary','plus'));sidebar.append(actions);
  const detail=node('article','detail');detail.id='detail';workspace.append(sidebar,detail);main.replaceChildren(workspace);renderList();renderDetail();
}
function renderList(){
  const list=$('entries');if(!list)return;list.replaceChildren();const entries=filteredEntries();
  if(!entries.length){const empty=node('li','empty');empty.append(icon('notebook'),node('h2','',t(query?'noResults':'empty')),node('p','',t(query?'noResultsHelp':'emptyHelp')));list.append(empty);return;}
  for(const entry of entries){const item=node('li'),btn=button(entry.title,()=>{selected=entry.id;revealed=false;renderWorkspace();},'entry-button');btn.replaceChildren();btn.setAttribute('aria-pressed',String(selected===entry.id));const info=node('span','entry-info');info.append(node('strong','',entry.title),node('small','',entry.account));btn.append(node('span','avatar',[...entry.title][0]?.toUpperCase()||'•'),info);item.append(btn);list.append(item);}
}
function renderDetail(){
  const detail=$('detail');if(!detail)return;detail.replaceChildren();const entry=session.vault.entries.find(e=>e.id===selected);
  if(!entry){selected=null;const empty=node('div','empty');empty.append(icon('notebook'),node('h2','',t('choose')),node('p','',t('chooseHelp')));detail.append(empty);return;}
  detail.append(button(t('back'),()=>{selected=null;revealed=false;renderWorkspace();},'icon-button mobile-back','back'));
  const top=node('div','detail-top');top.append(node('h1','',entry.title),button(t('edit'),()=>openEditor(entry),'pill'));detail.append(top,node('div','detail-folder',session.vault.folders.find(f=>f.id===entry.folderID)?.name||t('unfiled')));
  for(const name of ['account','password','notes']){
    const field=node('section','field');field.append(node('label','',t(name)));const value=node('div','field-value');
    value.append(node('div',name==='password'?'field-text secret':'field-text',name==='password'?(revealed?entry.password:'••••••••••••'):(entry[name]||t('noNotes'))));
    if(name!=='notes'){const actions=node('div','field-actions');if(name==='password')actions.append(button(t(revealed?'hide':'show'),()=>{revealed=!revealed;renderDetail();},'icon-button',revealed?'hide':'show'));actions.append(button(t('copy'),()=>copyText(entry[name]),'icon-button','copy'));value.append(actions);}field.append(value);detail.append(field);
  }
  const bottom=node('div','detail-bottom');bottom.append(button(t('delete'),()=>confirmDelete(t('deleteConfirm'),t('deleteHelp'),async()=>{const vault=structuredClone(session.vault);vault.entries=vault.entries.filter(e=>e.id!==entry.id);await saveVault(vault);selected=null;}),'icon-button','delete'));detail.append(bottom);
}
async function copyText(value){try{await navigator.clipboard.writeText(value);notify(t('copied'));}catch{notify(t('clipboard'));}}
function showDialog(title,kind){closeDialog();dialogKind=kind;dialog.dataset.kind=kind;const inner=node('div','dialog-inner'),header=node('div','dialog-header');header.append(node('h2','',title),button(t('close'),()=>editor?(kind==='editor'||kind==='discard'?cancelEditor():renderEditor()):closeDialog(),'icon-button','close'));inner.append(header);dialog.append(inner);dialog.showModal();return inner;}
async function saveVault(vault){if(!validTenon()){tenonIdentity=null;lock();throw {code:'locked'};}const conflicts=await session.save(vault,t('conflictCopy'));notify(t(conflicts?'conflicts':'saved'));}
function formField(label,value,type='text'){const wrap=node('div','form-field'),name=node('label','',t(label));name.htmlFor=`field-${label}`;const input=node(type==='textarea'?'textarea':'input');input.id=`field-${label}`;if(type!=='textarea')input.type=type;input.value=value;input.autocomplete='off';input.spellcheck=false;wrap.append(name,input);return{wrap,input};}
function openEditor(entry){
  if(!session.vault)return;editor=entry?{...entry}:{id:newID(),title:'',account:'',password:'',notes:''};renderEditor();
}
function renderEditor(){
  const inner=showDialog(t(session.vault.entries.some(e=>e.id===editor.id)?'edit':'newPassword'),'editor'),form=node('form');
  for(const name of ['title','account','password','notes']){const field=formField(name,editor[name],name==='notes'?'textarea':name==='password'?'password':'text');field.input.addEventListener('input',()=>editor[name]=field.input.value);
    if(name==='password'){field.wrap.removeChild(field.input);const row=node('div','password-input');row.append(field.input,button(t('generator'),()=>openGenerator(true),'icon-button','generator'));field.wrap.append(row);}form.append(field.wrap);}
  const group=node('div','form-field'),label=node('label','',t('folder')),select=node('select');label.htmlFor='folder-select';select.id='folder-select';
  for(const f of [{id:'',name:t('unfiled')},...session.vault.folders]){const option=node('option','',f.name);option.value=f.id;select.append(option);}select.value=editor.folderID||'';select.addEventListener('change',()=>{if(select.value)editor.folderID=select.value;else delete editor.folderID;});
  group.append(label,select,button(t('newFolder'),()=>openNewFolder(true),'text-button'));form.append(group);
  const actions=node('div','form-actions'),submit=node('button','pill primary',t('save'));submit.type='submit';actions.append(button(t('cancel'),cancelEditor),submit);form.append(actions);
  form.addEventListener('submit',async event=>{event.preventDefault();if(!editor.title.trim()||!editor.password){showError(form,{code:'required'});return;}const vault=structuredClone(session.vault),draft={...editor,title:editor.title.trim()},index=vault.entries.findIndex(e=>e.id===draft.id);if(index<0)vault.entries.push(draft);else vault.entries[index]=draft;setBusy(inner,true);submit.textContent=t('saving');
    try{await saveVault(vault);selected=draft.id;editor=null;closeDialog();render();}catch(error){if(error.code!=='locked')showError(form,error);}finally{setBusy(inner,false);submit.textContent=t('save');}});
  inner.append(form);$('field-title').focus();
}
function cancelEditor(){if(!editor)return closeDialog();const original=session.vault?.entries.find(e=>e.id===editor.id);const dirty=original?JSON.stringify(original)!==JSON.stringify(editor):['title','account','password','notes'].some(k=>editor[k]);if(!dirty){editor=null;closeDialog();return;}const inner=showDialog(t('discard'),'discard');inner.append(node('p','helper',t('discardHelp')));const actions=node('div','form-actions');actions.append(button(t('continueEditing'),renderEditor),button(t('discardButton'),()=>{editor=null;closeDialog();},'pill primary'));inner.append(actions);}
function openNewFolder(fromEditor=false){
  const inner=showDialog(t('newFolder'),'newFolder'),form=node('form'),field=formField('folderName','');field.input.required=true;form.append(field.wrap);const actions=node('div','form-actions');actions.append(button(t('cancel'),()=>fromEditor?renderEditor():openFolders()));const submit=node('button','pill primary',t('save'));submit.type='submit';actions.append(submit);form.append(actions);inner.append(form);
  form.addEventListener('submit',async event=>{event.preventDefault();const name=field.input.value.trim();if(!name)return;const vault=structuredClone(session.vault),folder={id:newID(),name};vault.folders.push(folder);setBusy(inner,true);try{await saveVault(vault);if(fromEditor&&editor){editor.folderID=folder.id;renderEditor();}else{render();openFolders();}}catch(error){if(error.code!=='locked')showError(form,error);}finally{setBusy(inner,false);}});field.input.focus();
}
function openFolders(){if(!session.vault)return;const inner=showDialog(t('folders'),'folders');for(const folder of session.vault.folders){const row=node('div','folder-row');row.append(icon('folder'),node('strong','',folder.name),button(t('deleteFolder'),()=>confirmDelete(t('deleteFolder'),t('deleteFolderHelp'),async()=>{const vault=structuredClone(session.vault);vault.folders=vault.folders.filter(f=>f.id!==folder.id);vault.entries.forEach(e=>{if(e.folderID===folder.id)delete e.folderID;});await saveVault(vault);if(filter===folder.id)filter='all';}),'icon-button','delete'));inner.append(row);}inner.append(button(t('newFolder'),()=>openNewFolder(),'pill','plus'));}
function confirmDelete(title,message,action){const inner=showDialog(title,'confirm');deletion={title,message,action};inner.append(node('p','helper',message));const actions=node('div','form-actions');actions.append(button(t('cancel'),closeDialog),button(t('confirm'),async()=>{setBusy(inner,true);try{await action();closeDialog();render();}catch(error){if(error.code!=='locked')showError(inner,error);}finally{setBusy(inner,false);}},'pill primary'));inner.append(actions);}
function openGenerator(fromEditor=false, retained=null){
  const inner=showDialog(t('generator'),'generator'),output=node('div','generated');output.setAttribute('aria-label',t('password'));output.tabIndex=0;inner.append(output);
  const label=node('label','helper',t('length'));label.htmlFor='password-length';inner.append(label);const controls=node('div','generator-controls'),range=node('input'),number=node('input');range.type='range';range.min='8';range.max='24';range.value='16';range.setAttribute('aria-label',t('length'));number.id='password-length';number.type='number';number.min='8';number.max='4096';number.step='1';number.value=retained?.length || '16';range.value=String(Math.min(24,Math.max(8,Number(number.value))));controls.append(range,number);inner.append(controls,node('p','helper',t('lengthHelp')));
  const checks={};for(const key of ['upper','lower','digits','symbols']){const row=node('label','check-row',t(key)),check=node('input');check.type='checkbox';check.id=`generator-${key}`;check.checked=retained?.characters[key] ?? true;checks[key]=check;row.append(check);inner.append(row);check.addEventListener('change',generate);}
  function generate(){inner.querySelector('.error')?.remove();try{generatorValue=generatePassword(Number(number.value),Object.fromEntries(Object.entries(checks).map(([k,v])=>[k,v.checked])));output.textContent=generatorValue;}catch(error){generatorValue='';output.textContent='';showError(inner,error);}}
  range.addEventListener('input',()=>{number.value=range.value;generate();});number.addEventListener('input',()=>{range.value=String(Math.min(24,Math.max(8,Number(number.value))));generate();});
  const actions=node('div','form-actions');actions.append(button(t('another'),generate),button(t(fromEditor?'use':'copyPassword'),async()=>{if(!generatorValue)return;const value=generatorValue;if(fromEditor&&editor)editor.password=value;await copyText(value);if(fromEditor&&editor)renderEditor();},'pill primary'));inner.append(actions,node('p','helper',t('clipboardHelp')));if(retained?.value){generatorValue=retained.value;output.textContent=generatorValue;}else generate();
}
function openSettings(){const inner=showDialog(t('settings'),'settings');inner.append(node('h3','',t('automaticLock')),node('p','helper',t('automaticLockHelp')),node('p','helper',t('browserHelp')));const row=node('div','settings-row'),label=node('label','',t('language')),select=node('select');label.htmlFor='app-language';select.id='app-language';for(const [value,text]of[['en','English'],['zh','简体中文']]){const option=node('option','',text);option.value=value;select.append(option);}select.value=language;select.addEventListener('change',()=>changeLanguage(select.value));row.append(label,select);inner.append(row);
  if(tenonIdentity)inner.append(node('h3','',language==='zh'?'Tenon 账号':'Tenon Account'),node('p','helper',tenonIdentity.name),button(language==='zh'?'退出 PassBy':'Sign out of PassBy',signOutTenon,'pill'));
  if(session.key){inner.append(button(t('refresh'),async()=>{setBusy(inner,true);try{await session.refresh();renderWorkspace();notify(t('refreshed'));}catch(error){if(error.code!=='locked')showError(inner,error);}finally{setBusy(inner,false);}},'pill'),button(t('lock'),lock,'pill'));}
  if(trustBinding)inner.append(button(language==='zh'?'撤销这台浏览器的授权':'Forget this browser',async()=>{
    try{await trustedBrowser.forget(trustBinding);trustedKey=null;trustBinding=null;lock();notify(language==='zh'?'已撤销浏览器授权':'Browser authorization removed');}catch{notify(t('browserStorage'));}
  },'pill'));
  inner.append(button(language==='zh'?'关于 PassBy':'About PassBy',openAbout,'pill'));
}
function openAbout(){
  const inner=showDialog(language==='zh'?'关于 PassBy':'About PassBy','about');
  const logo=node('div','wordmark');logo.setAttribute('role','img');logo.setAttribute('aria-label',language==='zh'?'PassBy，Tenon 出品':'PassBy, by Tenon');
  const mark=node('img','tenon-mark');mark.src='./web/tenon-mark.svg';mark.alt='';logo.append(node('span','','PassBy'),mark);
  const version=document.querySelector('meta[name="passby-version"]')?.content;
  inner.append(logo,node('p','helper',`${language==='zh'?'版本':'Version'}: ${version || (language==='zh'?'网页 · 本地构建':'Web · Local build')}`),
    node('p','about-description',language==='zh'?'PassBy 是你的私人密码本。将标题、账号、密码和备注保存在一起，按文件夹整理，并生成强密码，复制到其他应用中使用。':'PassBy is a private password notebook. Keep titles, accounts, passwords and notes together, organize them in folders, and generate strong passwords to copy into other apps.'),
    node('p','about-description',language==='zh'?'密码本先在设备上加密，再同步至 Apple 私有云存储。手机端离开应用即锁定，再次打开需要 Face ID。网页版使用恢复密钥在当前页面解密，离开窗口后自动锁定。':'Your notebook is encrypted on your device before syncing to Apple private storage. On iPhone, leaving the app locks it and Face ID unlocks it. The web app decrypts it with your recovery key and locks when you leave the window.'));
  const publisher=node('div','about-publisher'),publisherMark=node('img');publisherMark.src='./web/tenon-mark.svg';publisherMark.alt='';
  publisher.append(node('p','helper',language==='zh'?'出品方':'Publisher'),publisherMark,node('span','','榫卯 Tenon AI'));
  const website=node('a','about-website','tenon.asia');website.href='https://tenon.asia/';
  inner.append(publisher,website,button(t('back'),openSettings,'pill'));
}

render();
async function prepareTenon() {
  tenonLoading=true;tenonError=false;render();
  try {
    const response=await fetch('./api/auth/session',{cache:'no-store',credentials:'same-origin'});
    if(response.status===401){tenonIdentity=null;tenonError=tenonCallbackFailed;return;}
    if(!response.ok)throw Error('Service unavailable');
    const {identity}=await response.json();
    if(identity?.issuer!=='https://account.tenon.asia/api/auth'||typeof identity.sub!=='string'||!Number.isFinite(identity.expires)||identity.expires<=Date.now() || identity.expires>Date.now()+60000)throw Error('Invalid identity');
    tenonIdentity=identity;clearTimeout(tenonExpiry);
    tenonExpiry=setTimeout(()=>{tenonIdentity=null;lock();},Math.max(0,identity.expires-Date.now()));
    if(!signedIn)void prepareApple();
  } catch {tenonError=true;}
  finally {tenonLoading=false;render();}
}
async function signOutTenon() {
  if(tenonSigningOut)return;
  tenonSigningOut=true;lock();
  try {
    const response=await fetch('./api/auth/logout',{method:'POST',credentials:'same-origin'});
    if(!response.ok)throw Error('Service unavailable');
    tenonIdentity=null;trustedKey=null;trustBinding=null;clearTimeout(tenonExpiry);render();
  }catch{notify(language==='zh'?'退出未完成，请重试。密码本已锁定。':'Sign-out failed. Try again. Your notebook is locked.');}
  finally{tenonSigningOut=false;render();}
}
// This is CloudKit data authorization, not a second product account login.
Object.assign(copy.en,{connect:'Authorize Apple storage',switchAccount:'Change storage account',signInHelp:'Authorize the Apple Account that stores your iPhone notebook.',remember:'Keep Apple storage authorized on this trusted computer'});
Object.assign(copy.zh,{connect:'授权 Apple 云存储',switchAccount:'更换存储账号',signInHelp:'授权访问 iPhone 密码本所属 Apple 账号的私有云存储。',remember:'在这台可信电脑上保留 Apple 存储授权'});
if(new URLSearchParams(location.search).has('auth_error')){tenonError=true;history.replaceState(null,'',location.pathname);}
void prepareTenon();
