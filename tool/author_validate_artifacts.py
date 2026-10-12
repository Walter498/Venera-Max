#!/usr/bin/env python3
"""Validate real device/test-release products; fail closed before artifact upload."""
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import zipfile


def run(*args):
    print('+', ' '.join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), check=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    text = result.stdout.decode(errors='replace')
    print(text, flush=True)
    return text


version_match = re.search(r'^version:\s*(\S+)\s*$', Path('pubspec.yaml').read_text(), re.M)
assert version_match
version, build = version_match[1].split('+')
assert (version, build) == ('2.3.6', '249')
out = Path('build/author-artifacts')
out.mkdir(parents=True, exist_ok=True)

if sys.argv[1] == 'ios':
    app = Path('build/ios/iphoneos/Runner.app')
    assert app.is_dir(), 'Device Release Runner.app missing'
    with (app / 'Info.plist').open('rb') as f:
        info = plistlib.load(f)
    print('Runner plist:', {key: info.get(key) for key in (
        'CFBundleShortVersionString', 'CFBundleVersion', 'MinimumOSVersion',
        'DTPlatformName', 'DTSDKName', 'CFBundleSupportedPlatforms')})
    assert info['CFBundleShortVersionString'] == version
    assert info['CFBundleVersion'] == build
    assert info['DTPlatformName'] == 'iphoneos'
    assert info['DTSDKName'].startswith('iphoneos')
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert info['MinimumOSVersion'] == '16.0'
    executable = app / info['CFBundleExecutable']
    assert executable.is_file()
    magics = {bytes.fromhex(x) for x in ('feedface', 'cefaedfe', 'feedfacf',
                                       'cffaedfe', 'cafebabe', 'bebafeca',
                                       'cafebabf', 'bfbafeca')}
    checked = []
    for path in sorted(app.rglob('*')):
        if not path.is_file():
            continue
        with path.open('rb') as f:
            magic = f.read(4)
        if magic not in magics:
            continue
        arches = run('xcrun', 'lipo', '-archs', path).strip().split()
        assert 'arm64' in arches and set(arches) <= {'arm64', 'arm64e'}, (path, arches)
        loads = run('xcrun', 'otool', '-l', path)
        run('xcrun', 'vtool', '-show-build', path)
        platforms = re.findall(r'^\s*platform\s+(\S+)', loads, re.M)
        if platforms:
            assert all(p in ('2', 'IOS', 'iOS') for p in platforms), (path, platforms)
        else:
            assert 'LC_VERSION_MIN_IPHONEOS' in loads, f'No device platform: {path}'
        assert 'LC_VERSION_MIN_MACOSX' not in loads
        checked.append(path)
    assert executable in checked
    print('Validated device Mach-O count:', len(checked))
    payload = out / 'Payload'
    assert not payload.exists()
    payload.mkdir()
    shutil.copytree(app, payload / app.name, symlinks=True)
    ipa = out / f'VeneraX-ios-{version}+{build}-unsigned.ipa'
    subprocess.run(['zip', '-qry', str(ipa.resolve()), 'Payload'], cwd=out, check=True)
    with zipfile.ZipFile(ipa) as z:
        assert z.testzip() is None
        assert 'Payload/Runner.app/Info.plist' in z.namelist()
        assert 'Payload/Runner.app/' + info['CFBundleExecutable'] in z.namelist()
    shutil.rmtree(payload)
    print('UNSIGNED device IPA: requires signing/provisioning for installation.')
else:
    assert sys.argv[1] == 'android'
    assert os.environ.get('VENERA_TEST_SIGNING') == '1'
    sdk = Path(os.environ.get('ANDROID_SDK_ROOT') or os.environ['ANDROID_HOME'])
    tools = sorted((sdk / 'build-tools').iterdir(),
                   key=lambda p: tuple(map(int, re.findall(r'\d+', p.name))))
    tool = next(p for p in reversed(tools) if (p / 'apksigner').is_file() and (p / 'aapt').is_file())
    print('Actual Android build-tools:', tool)
    cert = subprocess.run(['keytool', '-exportcert', '-keystore',
                           str(Path.home() / '.android/debug.keystore'),
                           '-storepass', 'android', '-alias', 'androiddebugkey'],
                          check=True, stdout=subprocess.PIPE).stdout
    digest = hashlib.sha256(cert).hexdigest()
    abis = ['armeabi-v7a', 'arm64-v8a', 'x86_64']
    expected = {f'VeneraX-{version}.apk': (set(abis), int(build) * 10)}
    expected.update({f'VeneraX-{version}-{abi}.apk': ({abi}, int(build) * 10 + i)
                     for i, abi in enumerate(abis, 1)})
    release = Path('build/app/outputs/apk/release')
    assert {p.name for p in release.glob('*.apk')} == set(expected)
    for name, (required, code) in expected.items():
        apk = release / name
        badging = run(tool / 'aapt', 'dump', 'badging', apk)
        assert f"versionName='{version}'" in badging
        assert f"versionCode='{code}'" in badging
        assert "name='io.github.kyosee.venera'" in badging
        signature = run(tool / 'apksigner', 'verify', '--verbose', '--print-certs', apk)
        fingerprints = re.findall(r'certificate SHA-256 digest:\s*([0-9a-fA-F]+)', signature)
        assert fingerprints and all(p.lower() == digest for p in fingerprints)
        with zipfile.ZipFile(apk) as z:
            assert z.testzip() is None
            present = {n.split('/')[1] for n in z.namelist() if n.startswith('lib/')}
            assert present == required, (name, present, required)
            for abi in required:
                assert f'lib/{abi}/libflutter.so' in z.namelist()
                assert f'lib/{abi}/libapp.so' in z.namelist()
        shutil.copy2(apk, out / name)
        print('Validated TEST-signed Release:', name)
for artifact in sorted(out.iterdir()):
    if artifact.is_file():
        print('SHA256', hashlib.sha256(artifact.read_bytes()).hexdigest(), artifact.name)
