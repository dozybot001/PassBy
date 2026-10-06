import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { recoveryKey, openNotebook, sealNotebook, generatePassword } from '../public/web/crypto.mjs';
import { validateVault, mergeVault } from '../public/web/model.mjs';
import { NotebookSession } from '../public/web/session.mjs';
import { CloudNotebook } from '../public/web/cloud.mjs';
import { TENON_SESSION_TTL, validIdentity, scheduleExpiry, requestProductDeletion } from '../public/web/auth.mjs';
const id = '11111111-1111-4111-8111-111111111111';
const entry = {id,title:'Example',account:'example@test.invalid',password:'Test-Only-Password',notes:'兼容性'};
const vault = () => ({schemaVersion:1,folders:[],entries:[{...entry}]});
const raw = Uint8Array.from({length:32},(_,i)=>i);
const checksum = new Uint8Array(await crypto.subtle.digest('SHA-256',raw));
const text = Buffer.concat([raw,checksum.subarray(0,2)]).toString('hex');
const key = await recoveryKey(text);
test('Tenon identity accepts 30 days and rejects expired or excessive lifetimes',()=>{
  const now=1000000,identity={issuer:'https://account.tenon.asia/api/auth',sub:'fixture-user',role:'user',expires:now+TENON_SESSION_TTL};
  assert.equal(TENON_SESSION_TTL,2592000000);
  assert.equal(validIdentity(identity,now),true);
  assert.equal(validIdentity(identity,identity.expires-1),true);
  assert.equal(validIdentity(identity,identity.expires),false);
  assert.equal(validIdentity({...identity,expires:identity.expires+1},now),false);
  assert.equal(validIdentity({...identity,role:'unknown'},now),false);
});
test('30-day expiry uses bounded timers, expires once and can be cancelled after rescheduling',()=>{
  let now=1000000,queued,expired=0,cancelled;
  const options={now:()=>now,schedule:(callback,delay)=>{assert.ok(delay>0&&delay<=86400000);queued={callback,delay};return queued;},cancel:timer=>{cancelled=timer;}};
  const stop=scheduleExpiry(now+TENON_SESSION_TTL,()=>expired++,options);
  for(let day=0;day<29;day++){now+=queued.delay;queued.callback();assert.equal(expired,0);}
  now+=queued.delay;queued.callback();queued.callback();assert.equal(expired,1);
  stop();assert.equal(cancelled,queued);
  const cancelAfterReschedule=scheduleExpiry(now+TENON_SESSION_TTL,()=>expired++,options);
  now+=queued.delay;queued.callback();cancelAfterReschedule();
  now+=TENON_SESSION_TTL;queued.callback();assert.equal(expired,1);
});
test('recovery checksum, nonextractable key, AES-GCM authentication',async()=>{
  assert.equal(key.extractable,false);
  await assert.rejects(recoveryKey(text.slice(0,-2)+'00'),{code:'invalidKey'});
  await assert.rejects(recoveryKey('invalid'),{code:'invalidKey'});
  const sealed=await sealNotebook(vault(),key);
  assert.deepEqual(await openNotebook(sealed,key),vault());
  sealed[15]^=1;await assert.rejects(openNotebook(sealed,key),{code:'wrongKey'});
});
test('Swift CryptoKit ciphertext decrypts unchanged in WebCrypto',async()=>{
  const native=spawnSync('swift',['scripts/web-interop.swift','seal'],{encoding:'utf8'});
  assert.equal(native.status,0,native.stderr);
  const fixture=JSON.parse(native.stdout);
  assert.deepEqual(await openNotebook(Buffer.from(fixture.ciphertext,'base64'),await recoveryKey(fixture.recovery)),vault());
});
test('WebCrypto ciphertext opens unchanged in native CryptoKit',async()=>{
  const native=spawnSync('swift',['scripts/web-interop.swift','open'],{input:await sealNotebook(vault(),key)});
  assert.equal(native.status,0,native.stderr.toString());
  assert.deepEqual(JSON.parse(native.stdout.toString()),vault());
});
test('validation rejects invalid or duplicated references',()=>{
  const value=vault();value.entries.push({...entry,id:id.toLowerCase()});assert.throws(()=>validateVault(value),{code:'invalidNotebook'});
  const missing=vault();missing.entries[0].folderID=id;assert.throws(()=>validateVault(missing),{code:'invalidNotebook'});
  assert.throws(()=>validateVault({...vault(),schemaVersion:2}),{code:'version'});
});
test('merge preserves simultaneous edits and edit versus deletion',()=>{
  const base=vault(),local=vault(),remote=vault();local.entries[0].password='local';remote.entries[0].password='remote';
  const merged=mergeVault(base,local,remote);assert.equal(merged.conflicts,1);assert.equal(merged.vault.entries.length,2);assert.equal(merged.vault.entries[0].password,'remote');assert.equal(merged.vault.entries[1].password,'local');
  remote.entries=[];assert.equal(mergeVault(base,local,remote).vault.entries[0].password,'local');
});
test('generator supports bounds and each selected alphabet',()=>{
  for(const length of [8,16,24,256,4096]){const password=generatePassword(length);assert.equal(password.length,length);for(const regex of [/[A-Z]/,/[a-z]/,/[0-9]/,/[!@#$%^&*()\-_=+\[\]{};:,.?]/])assert.match(password,regex);}
  assert.match(generatePassword(16,{digits:true}),/^\d{16}$/);
  assert.throws(()=>generatePassword(7),{code:'invalidLength'});assert.throws(()=>generatePassword(4097),{code:'invalidLength'});assert.throws(()=>generatePassword(16,{}),{code:'selectCharacters'});
});
test('lock prevents an in-flight unlock from restoring secrets',async()=>{
  let finish;const cloud={fetch:()=>new Promise(resolve=>finish=resolve)};const session=new NotebookSession(cloud);
  const result=session.unlock(text);await new Promise(resolve=>setTimeout(resolve,10));session.lock();finish({record:{},bytes:await sealNotebook(vault(),key)});
  await assert.rejects(result,{code:'locked'});assert.equal(session.key,null);assert.equal(session.vault,null);
});
test('stale save retries with three-way merge and change tag',async()=>{
  let saves=0;const remote=vault();remote.entries[0].account='remote-edit';const cloud={fetch:async()=>({record:{recordChangeTag:String(saves)},bytes:await sealNotebook(remote,key)}),save:async(record,bytes)=>{saves++;if(saves===1)throw Object.assign(new Error(),{code:'conflict'});assert.equal(record.recordChangeTag,'1');assert.equal((await openNotebook(bytes,key)).entries.length,2);return record;}};
  const session=new NotebookSession(cloud);session.key=key;session.base=vault();session.vault=vault();const local=vault();local.entries[0].password='local-edit';assert.equal(await session.save(local),1);assert.equal(saves,2);
});
test('CloudKit transport accepts only Apple HTTPS assets, and uses encrypted Blob and change tag',async()=>{
  const cloud=new CloudNotebook(),originalFetch=globalThis.fetch;
  let url='https://cvws.icloud-content.com/file/${f}?token=example',saved;
  cloud.database={fetchRecords:async()=>({records:[{recordName:'notebook-v1',recordType:'Notebook',fields:{format:{value:1},ciphertext:{value:{downloadURL:url}}}}]}),saveRecords:async record=>{saved=record;return{records:[record]};}};
  globalThis.fetch=async assetURL=>{assert.equal(assetURL,'https://cvws.icloud-content.com/file/notebook.enc?token=example');return{ok:true,arrayBuffer:async()=>new ArrayBuffer(28)};};
  try{
    await cloud.fetch();
    url='https://icloud-content.com.attacker.invalid/file';await assert.rejects(cloud.fetch(),{code:'invalidNotebook'});
    url='http://cvws.icloud-content.com/file';await assert.rejects(cloud.fetch(),{code:'invalidNotebook'});
    const sealed=await sealNotebook(vault(),key);await cloud.save({recordName:'notebook-v1',recordChangeTag:'expected-tag'},sealed);
    assert.equal(saved.recordChangeTag,'expected-tag');assert.equal(saved.fields.format.value,1);
    // A browser POST must not introduce the octet-stream OPTIONS preflight.
    const upload = new Request('https://cws.icloud-content.com/test-only', {
      method: 'POST', body: saved.fields.ciphertext.value,
    });
    assert.equal(upload.headers.get('content-type'),'text/plain');
    assert.deepEqual(new Uint8Array(await upload.arrayBuffer()),new Uint8Array(sealed));
    assert.deepEqual(await openNotebook(await saved.fields.ciphertext.value.arrayBuffer(),key),vault());
    const native=spawnSync('swift',['scripts/web-interop.swift','open'],{input:Buffer.from(await saved.fields.ciphertext.value.arrayBuffer())});
    assert.equal(native.status,0,native.stderr.toString());
    assert.deepEqual(JSON.parse(native.stdout.toString()),vault());
    cloud.database.fetchRecords=async()=>({hasErrors:true,errors:[{ckErrorCode:'NOT_FOUND'}]});await assert.rejects(cloud.fetch(),{code:'noNotebook'});
    cloud.database.saveRecords=async()=>({hasErrors:true,errors:[{ckErrorCode:'CONFLICT'}]});await assert.rejects(cloud.save({},sealed),{code:'conflict'});
  }finally{globalThis.fetch=originalFetch;}
});

test('metadata precheck needs neither a recovery key nor an asset download',async()=>{
  const cloud=new CloudNotebook(),originalFetch=globalThis.fetch;
  const record={recordName:'notebook-v1',recordType:'Notebook',fields:{format:{value:1}}};
  cloud.database={fetchRecords:async()=>({records:[record]})};
  globalThis.fetch=()=>{throw new Error('Metadata must not download a vault');};
  try { assert.equal(await cloud.fetchRecord(),record); }
  finally { globalThis.fetch=originalFetch; }
});
test('Apple persistence is opt-in and obsolete auth callbacks are ignored',async()=>{
  const original=globalThis.CloudKit;
  const configurations=[],containers=[];
  let firstSignIn,firstSignOut;
  globalThis.CloudKit={
    configure:config=>{
      configurations.push(config);
      const container={privateCloudDatabase:{},setUpAuth:async()=>null,
        whenUserSignsIn:()=>new Promise(resolve=>{if(containers.length===1)firstSignIn=resolve;}),
        whenUserSignsOut:()=>new Promise(resolve=>{if(containers.length===1)firstSignOut=resolve;})};
      containers.push(container);
    },getDefaultContainer:()=>containers.at(-1),
  };
  try{
    const cloud=new CloudNotebook();let users=0,signOuts=0;
    await cloud.authenticate(()=>users++,()=>signOuts++,'en');
    assert.equal(configurations[0].containers[0].apiTokenAuth.persist,false);
    firstSignIn({});await new Promise(resolve=>setImmediate(resolve));assert.equal(users,1);
    await cloud.authenticate(()=>users++,()=>signOuts++,'zh',{remember:true,theme:'white'});
    assert.equal(configurations[1].containers[0].apiTokenAuth.persist,true);
    assert.equal(configurations[1].containers[0].apiTokenAuth.signInButton.theme,'white');
    firstSignOut();await new Promise(resolve=>setImmediate(resolve));assert.equal(signOuts,0);
  }finally{globalThis.CloudKit=original;}
});


test('authorized browser key opens ciphertext without a recovery phrase and remains non-exportable',async()=>{
  const cloud={fetch:async()=>({record:{},bytes:await sealNotebook(vault(),key)})};
  const session=new NotebookSession(cloud);
  await session.unlockWithKey(structuredClone(key));
  assert.deepEqual(session.vault,vault());
  await assert.rejects(crypto.subtle.exportKey('raw',session.key));
  session.lock();assert.equal(session.key,null);assert.equal(session.vault,null);
});
test('trusted browser authorization uses Tenon subject and Apple storage owner, never email',async()=>{
  const {bindingID}=await import('../public/web/trusted-browser.mjs');
  const a={issuer:'https://account.tenon.asia/api/auth',sub:'user-a',email:'same@example.test'};
  assert.notEqual(bindingID(a,'apple-a'),bindingID({...a,sub:'user-b'},'apple-a'));
  assert.notEqual(bindingID(a,'apple-a'),bindingID(a,'apple-b'));
  assert.throws(()=>bindingID(a,null),{code:'locked'});
  assert.throws(()=>bindingID({...a,issuer:'https://invalid.example'},'apple-a'),{code:'locked'});
});
test('product deletion starts from the local server and rejects an unregistered central destination', async () => {
  const request = 'x'.repeat(43);
  const target = `https://account.tenon.asia/account/delete/?request=${request}`;
  assert.equal(await requestProductDeletion(async (url, init) => {
    assert.equal(url, './api/auth/tenon/delete/start'); assert.equal(init.credentials, 'same-origin');
    assert.equal(init.method, 'POST'); assert.equal(init.body, '{}');
    return Response.json({ url: target });
  }), target);
  for (const url of ['https://attacker.invalid/account/delete/', 'https://account.tenon.asia/account/delete/?request=forged', target + '#spoof']) {
    await assert.rejects(requestProductDeletion(async () => Response.json({ url })));
  }
  await assert.rejects(requestProductDeletion(async () => new Response('', { status: 503 })));
});

test('website choices persist, invalid values keep prior choices, and blocked storage does not fail the page', async () => {
  const {readFileSync}=await import('node:fs');
  const {runInNewContext}=await import('node:vm');
  const script=readFileSync(new URL('../public/web/preferences.js',import.meta.url),'utf8');
  const boot=(search,saved={},blocked=false)=>{
    const values=new Map(Object.entries(saved)),root={dataset:{},lang:'en'};
    runInNewContext(script,{URLSearchParams,document:{documentElement:root},location:{search},localStorage:{getItem(key){if(blocked)throw Error();return values.get(key);},setItem(key,value){if(blocked)throw Error();values.set(key,value);}}});
    return {root,values};
  };
  const first=boot('?theme=dark&lang=zh',{'passby.theme':'light','passby.language':'en'});
  assert.deepEqual(first.root,{dataset:{theme:'dark',uiLanguage:'zh'},lang:'zh-CN'});
  assert.deepEqual(boot('',Object.fromEntries(first.values)).root,first.root);
  assert.deepEqual(boot('?theme=invalid&lang=fr',Object.fromEntries(first.values)).root,first.root);
  assert.deepEqual(boot('?theme=light&lang=en',{},true).root.dataset,{theme:'light',uiLanguage:'en'});
});
