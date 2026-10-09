#!/usr/bin/env python3
"""Publish a prepared IPA + update.json. Requires an existing, pushed version tag.
Uses Git's configured GitHub credential helper without printing or saving secrets.
"""
import json
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

# Refuse to publish an unpushed tag or replace an existing release silently.
call(f'{base}/git/ref/tags/{tag}')
try:
    call(f'{base}/releases/tags/{tag}')
except urllib.error.HTTPError as error:
    if error.code != 404:
        raise
else:
    raise SystemExit(f'Release {tag} already exists; inspect it before changing any assets.')
release = call(f'{base}/releases', 'POST', {'tag_name': tag, 'name': f"AssetFlow {manifest['version']}",
               'body': manifest['notes'] + '\n\n下载 AssetFlow.ipa，保存到文件，然后通过 SideStore 导入。使用原账号覆盖安装，不要删除已有应用。',
               'draft': True, 'prerelease': False})
upload = release['upload_url'].split('{')[0]
assert upload.startswith('https://uploads.github.com/'), 'Unexpected GitHub upload host'
for name, mime in [('AssetFlow.ipa', 'application/octet-stream'), ('update.json', 'application/json')]:
    call(f'{upload}?name={name}', 'POST', (folder / name).read_bytes(), mime)
published = call(f"{base}/releases/{release['id']}", 'PATCH', {'draft': False, 'make_latest': 'true'})
print('Published:', published['html_url'])
