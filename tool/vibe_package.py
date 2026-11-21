#!/usr/bin/env python3
"""CI-only packaging transformations; source identity/storage remain unchanged."""
from pathlib import Path
import hashlib, json, plistlib, shutil, subprocess, sys, zipfile

root = Path(__file__).resolve().parents[1]
base = 'a9734d29435081a70480831ba5dc45bec0e89066'
evidence = root / 'build/vibe-evidence'
evidence.mkdir(parents=True, exist_ok=True)

if sys.argv[1] == 'prepare':
    if subprocess.run(['git', 'cat-file', '-e', base], cwd=root, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode:
        subprocess.run(['git', 'fetch', '--no-tags', '--depth=1', 'origin', base], cwd=root, check=True)
    frozen = ['lib/pages/reader', 'lib/foundation', 'lib/main.dart', 'ios/Runner/AppDelegate.swift', 'test/goldens', 'test/reader_hud_render_test.dart', 'test/reader_hud_integration_test.dart']
    subprocess.run(['git', 'diff', '--exit-code', base, 'HEAD', '--', *frozen], cwd=root, check=True)
    (evidence / 'frozen-scope.json').write_text(json.dumps({'base': base, 'unchanged': frozen}, indent=2))
    project = root / 'ios/Runner.xcodeproj/project.pbxproj'
    text = project.read_text()
    assert 'PRODUCT_BUNDLE_IDENTIFIER = io.github.kyosee.venera;' in text
    project.write_text(text.replace('CODE_SIGN_STYLE = Automatic;', 'CODE_SIGN_STYLE = Manual; CODE_SIGN_IDENTITY = ""; CODE_SIGNING_REQUIRED = NO; CODE_SIGNING_ALLOWED = NO;'))
    info = root / 'ios/Runner/Info.plist'
    data = plistlib.loads(info.read_bytes())
    data['CFBundleDisplayName'] = 'VeneraX Vibe'
    info.write_bytes(plistlib.dumps(data, sort_keys=False))
    print('Prepared unsigned build; original bundle ID, app group, scheme and storage preserved.')
elif sys.argv[1] == 'package':
    app = root / 'build/ios/iphoneos/Runner.app'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundleIdentifier'] == 'io.github.kyosee.venera', info['CFBundleIdentifier']
    assert info['CFBundleShortVersionString'] == '3.0.0', info['CFBundleShortVersionString']
    assert info['CFBundleVersion'] == '3003', info['CFBundleVersion']
    assert info['CFBundleDisplayName'] == 'VeneraX Vibe', info['CFBundleDisplayName']
    output = root / 'build/vibe-package'
    payload = output / 'Payload'
    payload.mkdir(parents=True, exist_ok=True)
    shutil.copytree(app, payload / 'Runner.app', symlinks=True, dirs_exist_ok=True)
    name = 'VeneraX-Vibe-Test-3.0.0+3003.ipa'
    subprocess.run(['zip', '-qry', name, 'Payload'], cwd=output, check=True)
    ipa = output / name
    with zipfile.ZipFile(ipa) as archive:
        assert archive.testzip() is None
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    manifest = {'source_commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip(), 'base_commit': base, 'filename': name, 'sha256': digest, 'bytes': ipa.stat().st_size, 'bundle_id': info['CFBundleIdentifier'], 'display_name': info['CFBundleDisplayName'], 'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'], 'minimum_os': info.get('MinimumOSVersion'), 'device_family': info.get('UIDeviceFamily'), 'installation': 'overwrite, original app group and storage unchanged', 'signing': 'unsigned, user signs', 'ci_transforms': ['disable automatic code signing', 'CFBundleDisplayName=VeneraX Vibe', 'flutter build number=3003'], 'device_tested': False}
    (output / 'manifest.json').write_text(json.dumps(manifest, indent=2))
    (output / 'SHA256.txt').write_text(f'{digest}  {name}\n')
    (evidence / 'artifact-manifest.json').write_text(json.dumps(manifest, indent=2))
    print(json.dumps(manifest, indent=2))
else:
    raise SystemExit('Usage: vibe_package.py prepare|package')
