import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { recoveryKey, openNotebook, sealNotebook, generatePassword } from '../public/web/crypto.mjs';
import { validateVault, mergeVault } from '../public/web/model.mjs';
import { NotebookSession } from '../public/web/session.mjs';
const id = '11111111-1111-4111-8111-111111111111';
const entry = {id,title:'Example',account:'example@test.invalid',password:'Test-Only-Password',notes:'兼容性'};
const vault = () => ({schemaVersion:1,folders:[],entries:[{...entry}]});
const raw = Uint8Array.from({length:32},(_,i)=>i);
const checksum = new Uint8Array(await crypto.subtle.digest('SHA-256',raw));
const text = Buffer.concat([raw,checksum.subarray(0,2)]).toString('hex');
const key = await recoveryKey(text);
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
