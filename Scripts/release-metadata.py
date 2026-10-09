#!/usr/bin/env python3
"""Create update metadata from the actual device IPA, never from a guessed version."""
import json
import plistlib
import sys
import zipfile
from pathlib import Path

ipa = Path(sys.argv[1])
with zipfile.ZipFile(ipa) as archive:
    assert archive.testzip() is None, 'Damaged IPA'
    names = archive.namelist()
    assert not any(part.startswith('._') or part == '__MACOSX' for name in names for part in name.split('/')), 'macOS metadata must not be included in IPA'
    roots = {name.split('/')[1] for name in names if name.startswith('Payload/') and len(name.split('/')) > 1 and name.split('/')[1]}
    assert roots == {'AssetFlow.app'}, 'Payload must contain exactly one app bundle'
    info = plistlib.loads(archive.read('Payload/AssetFlow.app/Info.plist'))
    assert info['CFBundleIdentifier'] == 'com.modest.AssetFlow'
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert archive.read('Payload/AssetFlow.app/AssetFlow')[:4] == bytes.fromhex('cffaedfe')
version = info['CFBundleShortVersionString']
build = info['CFBundleVersion']
base = f'https://github.com/yxiao-yang/AssetFlow/releases'
manifest = {
    'version': version,
    'build': build,
    'minimumOS': info['MinimumOSVersion'],
    'notes': Path(sys.argv[3]).read_text() if len(sys.argv) > 3 else '更新内容请查看发布说明。',
    'releaseURL': f'{base}/tag/v{version}',
    'downloadURL': f'{base}/download/v{version}/AssetFlow.ipa',
}
Path(sys.argv[2]).write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')
print(f'Validated device IPA: {version} ({build})')
