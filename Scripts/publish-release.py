#!/usr/bin/env python3
"""Publish a prepared IPA + update.json. Requires an existing, pushed version tag.
Uses Git's configured GitHub credential helper without printing or saving secrets.
"""
import json
import hashlib
import os
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

folder = Path(sys.argv[1])
manifest = json.loads((folder / 'update.json').read_text())
tag = f"v{manifest['version']}"
expected = f'https://github.com/yxiao-yang/AssetFlow/releases/download/{tag}/AssetFlow.ipa'
assert manifest['downloadURL'] == expected
credential = subprocess.run(['git', 'credential', 'fill'], input='protocol=https\nhost=github.com\n\n',
                            text=True, capture_output=True, check=True, timeout=15,
                            env={**os.environ, 'GIT_TERMINAL_PROMPT': '0'})
fields = dict(line.split('=', 1) for line in credential.stdout.splitlines() if '=' in line)
headers = {'Authorization': 'Bearer ' + fields['password'], 'Accept': 'application/vnd.github+json',
           'X-GitHub-Api-Version': '2022-11-28'}
base = 'https://api.github.com/repos/yxiao-yang/AssetFlow'

def call(url, method='GET', data=None, content_type='application/json'):
    body = json.dumps(data).encode() if isinstance(data, dict) else data
    request = urllib.request.Request(url, data=body, method=method,
                                     headers={**headers, 'Content-Type': content_type})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)

# An interrupted upload stays a draft. Resume only when explicitly requested.
call(f'{base}/git/ref/tags/{tag}')
existing = next((r for r in call(f'{base}/releases?per_page=100') if r['tag_name'] == tag), None)
if existing:
    if not existing['draft'] or '--resume-draft' not in sys.argv[2:]:
        raise SystemExit(f'Release {tag} already exists. Only an unfinished draft can be resumed with --resume-draft.')
    release = existing
else:
    release = call(f'{base}/releases', 'POST', {'tag_name': tag, 'name': f"AssetFlow {manifest['version']}",
                   'body': manifest['notes'] + '\n\n下载 AssetFlow.ipa，保存到文件，然后通过 SideStore 导入。使用原账号覆盖安装，不要删除已有应用。',
                   'draft': True, 'prerelease': False})
upload = release['upload_url'].split('{')[0]
assert upload.startswith('https://uploads.github.com/'), 'Unexpected GitHub upload host'
for name, mime in [('AssetFlow.ipa', 'application/octet-stream'), ('update.json', 'application/json')]:
    file = folder / name
    prior = next((a for a in release.get('assets', []) if a['name'] == name), None)
    if prior:
        digest = 'sha256:' + hashlib.sha256(file.read_bytes()).hexdigest()
        if prior['state'] != 'uploaded' or prior.get('digest') != digest:
            raise SystemExit(f'Existing {name} differs or is incomplete. Inspect the draft; no asset was replaced.')
        continue
    # Pass credentials via stdin, not process arguments or a file. Do not follow redirects.
    config = '\n'.join(['url = ' + json.dumps(f'{upload}?name={name}'), 'request = "POST"',
                        'header = ' + json.dumps('Authorization: Bearer ' + fields['password']),
                        'header = ' + json.dumps('Content-Type: ' + mime),
                        'data-binary = ' + json.dumps('@' + str(file.resolve()))])
    result = subprocess.run(['curl', '--config', '-', '--fail', '--silent', '--show-error',
                             '--connect-timeout', '20', '--max-time', '60'],
                            input=config, text=True, capture_output=True, timeout=65)
    if result.returncode:
        raise SystemExit(f'Upload failed for {name}. The release remains a draft; retry with --resume-draft. ' + result.stderr)
    asset = json.loads(result.stdout)
    assert asset['state'] == 'uploaded' and asset['size'] == file.stat().st_size
published = call(f"{base}/releases/{release['id']}", 'PATCH', {'draft': False, 'make_latest': 'true'})
print('Published:', published['html_url'])
