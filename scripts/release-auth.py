"""Verify the immutable PassBy identity bundle, test a candidate, then switch ingress."""
import hashlib,json,pathlib,sys,subprocess,tarfile,time,re,urllib.request,urllib.error,shutil,os

sha=sys.argv[1]
assert re.fullmatch('[0-9a-f]{40}',sha)
base=pathlib.Path('/opt/passby-auth'); base.mkdir(exist_ok=True)
lock=pathlib.Path('/opt/passby-site/.publish-lock'); lock.mkdir()
site=pathlib.Path('/etc/caddy/sites-enabled/tenon-ai.caddy'); before=site.read_bytes()
web_site=pathlib.Path('/etc/caddy/sites-enabled/passby.caddy'); web_before=web_site.read_bytes() if web_site.exists() else None
active=base/'active.json'; previous=json.loads(active.read_text()) if active.exists() else {}
port=7281 if previous.get('port')==7280 else 7280
name=f'passby-auth-{sha[:12]}-{port}'
release=base/'releases'/sha
image='docker.m.daocloud.io/library/node@sha256:235600a8101ab264e117b1768e925532262668dc9b581ef1dd7d96ced463b8e7'
changed=False; started=False; previous_stopped=False
run=lambda args,**kw:subprocess.run(args,check=True,**kw)
def request(url,expected,sqlite=False):
 try:
  with urllib.request.urlopen(url,timeout=5) as response:status=response.status;headers=response.headers;body=response.read()
 except urllib.error.HTTPError as error:status=error.code;headers=error.headers
 assert status==expected,f'Unexpected status {status}'
 assert headers.get('Cache-Control')=='no-store' and headers.get('Referrer-Policy')=='no-referrer','Identity privacy headers missing'
 if sqlite:
  result=json.loads(body)
  assert result.get('ok') is True and result.get('sessionStorage')=='sqlite','Persistent session storage is unavailable'
try:
 assert (base/'config/tenon.env').stat().st_mode&0o777==0o600,'Private configuration must be 0600'
 if not release.exists():
  release.mkdir(parents=True)
  with tarfile.open(f'/tmp/passby-auth-{sha}.tar.gz') as bundle:bundle.extractall(release,filter='data')
 manifest=json.loads((release/'manifest.json').read_text()); assert manifest['commit']==sha
 actual={str(p.relative_to(release)):hashlib.sha256(p.read_bytes()).hexdigest() for p in release.rglob('*') if p.is_file() and p not in [release/'manifest.json',release/'ingress-before.caddy']}
 assert actual==manifest['files'],'Release checksum mismatch'
 for p in release.rglob('*'):p.chmod(0o555 if p.is_dir() else 0o444)
 release.chmod(0o555)
 tests=sorted(str(path.relative_to(release/'server')) for path in (release/'server/test').glob('*.test.mjs'))
 assert tests,'Authentication tests are missing'
 isolated=['docker','run','--rm','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--user','10001:10001','--tmpfs','/tmp:rw,noexec,nosuid,nodev,size=64m,mode=1777','--mount',f'type=bind,src={release}/server,dst=/app,readonly','--workdir','/app']
 run(isolated+[image,'node','--input-type=module','-e',"import { DatabaseSync } from 'node:sqlite'; if (Number(process.versions.node.split('.')[0]) < 24) throw Error('Node 24 or newer is required'); const db = new DatabaseSync(':memory:'); db.close();"])
 run(isolated+[image,'node','--test',*tests])
 if previous.get('commit')==sha:
  request('https://tenon.asia/passby/api/health',200,sqlite=True);print('This authentication release is already active.');sys.exit()
 # No snapshot: the database holds only session digests and tombstones the
 # central service also enforces, and restoring one would revive logouts.
 data=base/'data';database=data/'sessions.sqlite'
 data.mkdir(mode=0o700,exist_ok=True)
 assert data.is_dir() and not data.is_symlink(),'Session storage must use a real directory'
 data.chmod(0o700)
 os.chown(data,10001,10001)
 if database.exists():
  assert database.is_file() and not database.is_symlink(),'Session database must be a regular file'
  os.chown(database,10001,10001);database.chmod(0o600)
 args=['docker','run','-d','--name',name,'--restart','unless-stopped','--network','host','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--user','10001:10001','--memory','192m','--cpus','0.5','--pids-limit','64','--mount',f'type=bind,src={release}/server,dst=/app,readonly','--mount',f'type=bind,src={data},dst=/data','--workdir','/app','--env-file',str(base/'config/tenon.env'),'--env',f'PORT={port}','--env','SESSION_DB=/data/sessions.sqlite',image,'node','server.mjs']
 run(args,stdout=subprocess.DEVNULL);started=True
 for attempt in range(20):
  try:request(f'http://127.0.0.1:{port}/passby/api/health',200,sqlite=True);break
  except Exception:
   if attempt==19:raise
   time.sleep(.25)
 request(f'http://127.0.0.1:{port}/api/health',200,sqlite=True)
 request(f'http://127.0.0.1:{port}/api/auth/session',401)
 metadata=database.stat()
 assert database.is_file() and not database.is_symlink() and metadata.st_uid==10001 and metadata.st_gid==10001 and metadata.st_mode&0o777==0o600,'Session database must be owned by 10001:10001 with mode 0600'
 route=f'\t# BEGIN PASSBY AUTH\n\thandle /passby/api/* {{\n\t\theader {{\n\t\t\tCache-Control \"no-store\"\n\t\t\tReferrer-Policy \"no-referrer\"\n\t\t}}\n\t\treverse_proxy 127.0.0.1:{port}\n\t}}\n\t# END PASSBY AUTH\n'
 content=re.sub(r'\t# BEGIN PASSBY AUTH\n.*?\t# END PASSBY AUTH\n','',before.decode(),flags=re.S)
 assert content.count('\t# BEGIN PASSBY\n')==1
 content=content.replace('\t# BEGIN PASSBY\n','\t# BEGIN PASSBY\n'+route,1)
 candidate=base/'candidate-sites';shutil.rmtree(candidate,ignore_errors=True);shutil.copytree('/etc/caddy/sites-enabled',candidate)
 (candidate/'tenon-ai.caddy').write_text(content)
 web_content=None
 if web_before is not None:
  web_content=re.sub(r'reverse_proxy 127\.0\.0\.1:728[01]',f'reverse_proxy 127.0.0.1:{port}',web_before.decode())
  assert web_content!=web_before.decode() or previous.get('port')==port
  (candidate/'passby.caddy').write_text(web_content)
 # Validate through the root config, which defines shared snippets such as access_log.
 line='import /etc/caddy/sites-enabled/*.caddy';root=pathlib.Path('/etc/caddy/Caddyfile').read_text()
 assert root.count(line)==1,'Unexpected Caddy root config'
 check=base/'candidate-Caddyfile';check.write_text(root.replace(line,'import '+str(candidate)+'/*.caddy'))
 run(['caddy','validate','--config',str(check),'--adapter','caddyfile'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 assert site.read_bytes()==before,'Ingress changed during release'
 # The first deletion-aware release must drain the previous writer before it
 # becomes reachable. Older callbacks do not carry the deletion generation.
 if previous.get('container'):
  run(['docker','stop',previous['container']],stdout=subprocess.DEVNULL);previous_stopped=True
 (release/'ingress-before.caddy').write_bytes(before)
 temp=site.with_suffix('.candidate');temp.write_text(content);os.replace(temp,site);changed=True
 if web_content is not None:
  temp=web_site.with_suffix('.candidate');temp.write_text(web_content);os.replace(temp,web_site)
 run(['systemctl','reload','caddy'])
 if web_content is not None:
  request('https://passby.tenon.asia/api/health',200,sqlite=True);request('https://passby.tenon.asia/api/auth/session',401)
 request('https://tenon.asia/passby/api/health',200,sqlite=True);request('https://tenon.asia/passby/api/auth/session',401)
 (base/'current-route.caddy').write_text(route)
 state={'commit':sha,'previous':previous.get('commit'),'port':port,'container':name,'image':image,'sessionDatabase':str(database)}
 temp=active.with_suffix('.candidate');temp.write_text(json.dumps(state));os.replace(temp,active)
 print('PassBy identity service deployed and public health/session checks passed: '+sha)
except BaseException:
 # Roll back code and ingress only: restoring an older database could revive
 # sessions that were logged out or rotated after the snapshot.
 if previous_stopped:run(['docker','start',previous['container']],stdout=subprocess.DEVNULL)
 if changed:
  site.write_bytes(before)
  if web_before is not None:web_site.write_bytes(web_before)
  run(['systemctl','reload','caddy'])
 if started:subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 raise
finally:
 lock.rmdir()
