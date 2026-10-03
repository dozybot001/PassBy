"""Verify the immutable PassBy identity bundle, test a candidate, then switch ingress."""
import hashlib,json,pathlib,sys,subprocess,tarfile,time,re,urllib.request,urllib.error,shutil,os
sha=sys.argv[1]
assert re.fullmatch('[0-9a-f]{40}',sha)
base=pathlib.Path('/opt/passby-auth'); base.mkdir(exist_ok=True)
lock=pathlib.Path('/opt/passby-site/.publish-lock'); lock.mkdir()
site=pathlib.Path('/etc/caddy/sites-enabled/tenon-ai.caddy'); before=site.read_bytes()
active=base/'active.json'; previous=json.loads(active.read_text()) if active.exists() else {}
port=7281 if previous.get('port')==7280 else 7280
name=f'passby-auth-{sha[:12]}-{port}'
release=base/'releases'/sha
image='docker.m.daocloud.io/library/node@sha256:235600a8101ab264e117b1768e925532262668dc9b581ef1dd7d96ced463b8e7'
changed=False; started=False
run=lambda args,**kw:subprocess.run(args,check=True,**kw)
def request(url,expected):
 try:
  with urllib.request.urlopen(url,timeout=5) as response:status=response.status;headers=response.headers
 except urllib.error.HTTPError as error:status=error.code;headers=error.headers
 assert status==expected,f'Unexpected status {status}'
 assert headers.get('Cache-Control')=='no-store' and headers.get('Referrer-Policy')=='no-referrer','Identity privacy headers missing'
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
 args=['docker','run','--rm','--network','none','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--user','10001:10001','--mount',f'type=bind,src={release}/server,dst=/app,readonly','--workdir','/app',image,'node','--test','test/auth.test.mjs']
 run(args)
 if previous.get('commit')==sha:
  request('https://tenon.asia/passby/api/health',200);print('This authentication release is already active.');sys.exit()
 args=['docker','run','-d','--name',name,'--restart','unless-stopped','--network','host','--read-only','--cap-drop','ALL','--security-opt','no-new-privileges','--user','10001:10001','--memory','192m','--cpus','0.5','--pids-limit','64','--mount',f'type=bind,src={release}/server,dst=/app,readonly','--workdir','/app','--env-file',str(base/'config/tenon.env'),'--env',f'PORT={port}',image,'node','server.mjs']
 run(args,stdout=subprocess.DEVNULL);started=True
 for attempt in range(20):
  try:request(f'http://127.0.0.1:{port}/passby/api/health',200);break
  except Exception:
   if attempt==19:raise
   time.sleep(.25)
 route=f'\t# BEGIN PASSBY AUTH\n\thandle /passby/api/* {{\n\t\theader {{\n\t\t\tCache-Control \"no-store\"\n\t\t\tReferrer-Policy \"no-referrer\"\n\t\t}}\n\t\treverse_proxy 127.0.0.1:{port}\n\t}}\n\t# END PASSBY AUTH\n'
 content=re.sub(r'\t# BEGIN PASSBY AUTH\n.*?\t# END PASSBY AUTH\n','',before.decode(),flags=re.S)
 assert content.count('\t# BEGIN PASSBY\n')==1
 content=content.replace('\t# BEGIN PASSBY\n','\t# BEGIN PASSBY\n'+route,1)
 candidate=base/'candidate-sites';shutil.rmtree(candidate,ignore_errors=True);shutil.copytree('/etc/caddy/sites-enabled',candidate)
 (candidate/'tenon-ai.caddy').write_text(content)
 root='import '+str(candidate)+'/*.caddy\n'
 check=base/'candidate-Caddyfile';check.write_text(root)
 run(['caddy','validate','--config',str(check),'--adapter','caddyfile'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 assert site.read_bytes()==before,'Ingress changed during release'
 (release/'ingress-before.caddy').write_bytes(before)
 temp=site.with_suffix('.candidate');temp.write_text(content);os.replace(temp,site);changed=True
 run(['systemctl','reload','caddy'])
 request('https://tenon.asia/passby/api/health',200);request('https://tenon.asia/passby/api/auth/session',401)
 (base/'current-route.caddy').write_text(route)
 state={'commit':sha,'port':port,'container':name,'image':image}
 temp=active.with_suffix('.candidate');temp.write_text(json.dumps(state));os.replace(temp,active)
 if previous.get('container'):subprocess.run(['docker','stop',previous['container']],stdout=subprocess.DEVNULL)
 print('PassBy identity service deployed and public health/session checks passed: '+sha)
except BaseException:
 if changed:site.write_bytes(before);run(['systemctl','reload','caddy'])
 if started:subprocess.run(['docker','rm','-f',name],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
 raise
finally:
 lock.rmdir()
