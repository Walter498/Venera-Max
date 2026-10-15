#!/usr/bin/env python3
"""Fail-closed release device IPA verification; no signing or publication."""
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
import zipfile

MAGICS = {bytes.fromhex(x) for x in ('feedface', 'cefaedfe', 'feedfacf',
          'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca')}


def run(*args):
    print('+', ' '.join(map(str, args)), flush=True)
    result = subprocess.run(list(map(str, args)), stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT)
    text = result.stdout.decode(errors='replace')
    print(text, flush=True)
    result.check_returncode()
    return text


def verify_plist(info, version, build):
    assert info['CFBundleShortVersionString'] == version
    assert info['CFBundleVersion'] == build
    assert info['DTPlatformName'] == 'iphoneos'
    assert info['DTSDKName'].startswith('iphoneos')
    assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS']
    assert info['MinimumOSVersion'] == '16.0'
    assert info['CFBundleIdentifier'] == 'io.github.kyosee.venera'
    executable = info['CFBundleExecutable']
    assert executable and '/' not in executable and executable not in ('.', '..')


def verify_platform(arches, loads):
    assert 'arm64' in arches and set(arches) <= {'arm64', 'arm64e'}, arches
    platforms = re.findall(r'^\s*platform\s+(\S+)', loads, re.M)
    if platforms:
        assert all(p in ('2', 'IOS', 'iOS') for p in platforms), platforms
    else:
        assert 'LC_VERSION_MIN_IPHONEOS' in loads, 'No device platform'
    assert 'LC_VERSION_MIN_MACOSX' not in loads
    assert 'LC_VERSION_MIN_IPHONESIMULATOR' not in loads


def verify_zip(ipa, info):
    with zipfile.ZipFile(ipa) as archive:
        assert archive.testzip() is None
        names = archive.namelist()
        assert len(set(names)) == len(names), 'duplicate ZIP entries'
        assert all(n.startswith('Payload/Runner.app/') or n in ('Payload/', 'Payload/Runner.app/') for n in names)
        assert all('..' not in Path(n).parts and not n.startswith('/') for n in names)
        assert plistlib.loads(archive.read('Payload/Runner.app/Info.plist')) == info
        assert archive.getinfo('Payload/Runner.app/' + info['CFBundleExecutable']).file_size > 0


def validate():
    match = re.search(r'^version:\s*(\S+)\s*$', Path('pubspec.yaml').read_text(), re.M)
    assert match, 'pubspec version missing'
    version, build = match[1].split('+')
    assert (version, build) == ('2.3.6', '256'), 'root must finalize 2.3.6+256'
    out = Path('build/comments-artifacts')
    out.mkdir(parents=True, exist_ok=True)
    evidence = Path(os.environ['RUNNER_TEMP']) / 'venera-comments-evidence'
    app = Path('build/ios/iphoneos/Runner.app')
    assert app.is_dir(), 'Device Release Runner.app missing'
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    verify_plist(info, version, build)
    run('plutil', '-lint', app / 'Info.plist')
    assert not list(app.rglob('embedded.mobileprovision')), 'provisioning profile forbidden'
    assert not (app / '_CodeSignature').exists(), 'Runner code signature forbidden'
    executable = app / info['CFBundleExecutable']
    assert executable.is_file()
    signature = subprocess.run(['codesign', '-dv', str(executable)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    print(signature.stdout.decode(errors='replace'), flush=True)
    assert signature.returncode != 0, 'Runner must be unsigned, not ad-hoc or identity signed'
    checked = []
    for path in sorted(app.rglob('*')):
        if not path.is_file():
            continue
        with path.open('rb') as stream:
            magic = stream.read(4)
        if magic not in MAGICS:
            continue
        arches = run('xcrun', 'lipo', '-archs', path).strip().split()
        loads = run('xcrun', 'otool', '-l', path)
        verify_platform(arches, loads)
        run('xcrun', 'vtool', '-show-build', path)
        checked.append(dict(path=str(path.relative_to(app)), arches=arches))
    assert any(x['path'] == info['CFBundleExecutable'] for x in checked)
    # Package only after all device/platform/signature gates pass.
    ipa = out / f'VeneraX-ios-comments-{version}+{build}-unsigned.ipa'
    with tempfile.TemporaryDirectory(prefix='comments-ipa-') as directory:
        payload = Path(directory) / 'Payload'
        payload.mkdir()
        shutil.copytree(app, payload / app.name, symlinks=True)
        subprocess.run(['zip', '-qry', str(ipa.resolve()), 'Payload'], cwd=directory, check=True)
    verify_zip(ipa, info)
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    (out / (ipa.name + '.sha256')).write_text(f'{digest}  {ipa.name}\n')
    report = dict(commit=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
                  local_baseline='fa7afe19c986d959d0125839756db78510b21775',
                  baseline='5290afd9ceeaeedda63ed54fff6b15a57c6c5674',
                  baseline_tree='b0a56c3a52b47ea79986eade62c90218e1e6f593',
                  version=version, build=build, unsigned=True, installable_without_signing=False,
                  platform='iphoneos', plist=info, macho=checked,
                  ipa=ipa.name, bytes=ipa.stat().st_size, sha256=digest)
    # Plists can contain bytes/dates: concise verification fields are serializable.
    report['plist'] = {key: info[key] for key in ('CFBundleIdentifier', 'CFBundleExecutable',
                       'CFBundleShortVersionString', 'CFBundleVersion', 'DTPlatformName',
                       'DTSDKName', 'CFBundleSupportedPlatforms', 'MinimumOSVersion')}
    encoded = json.dumps(report, indent=2) + '\n'
    (out / 'ipa-validation.json').write_text(encoded)
    (evidence / 'ipa-validation.json').write_text(encoded)
    print(encoded, flush=True)
    print('UNSIGNED device IPA: requires user signing/provisioning; no install or Release performed.')


class SelfTests(unittest.TestCase):
    def test_zip_structure(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'parser-fixture.zip'
            info = {'CFBundleExecutable': 'Runner'}
            with zipfile.ZipFile(path, 'w') as archive:
                archive.writestr('Payload/Runner.app/Info.plist', plistlib.dumps(info))
                archive.writestr('Payload/Runner.app/Runner', b'parser-only-fixture')
            verify_zip(path, info)
            with zipfile.ZipFile(path, 'a') as archive:
                archive.writestr('../unexpected', b'bad')
            with self.assertRaises(AssertionError):
                verify_zip(path, info)

    def test_platform_fail_closed(self):
        verify_platform(['arm64'], ' platform 2\n')
        verify_platform(['arm64'], 'LC_VERSION_MIN_IPHONEOS')
        for arches, loads in [(['x86_64'], ' platform 2\n'), (['arm64'], ' platform 7\n'),
                              (['arm64'], 'LC_VERSION_MIN_MACOSX'), (['arm64'], '')]:
            with self.assertRaises(AssertionError):
                verify_platform(arches, loads)

    def test_plist_fail_closed(self):
        info = dict(CFBundleShortVersionString='2.3.6', CFBundleVersion='250',
                    DTPlatformName='iphoneos', DTSDKName='iphoneos18.5',
                    CFBundleSupportedPlatforms=['iPhoneOS'], MinimumOSVersion='16.0',
                    CFBundleIdentifier='io.github.kyosee.venera', CFBundleExecutable='Runner')
        verify_plist(info, '2.3.6', '250')
        for key, value in [('CFBundleVersion', '249'), ('DTPlatformName', 'iphonesimulator'),
                           ('CFBundleSupportedPlatforms', ['iPhoneSimulator']),
                           ('CFBundleExecutable', '../Runner')]:
            with self.assertRaises(AssertionError):
                verify_plist(dict(info, **{key: value}), '2.3.6', '250')


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        unittest.main(argv=[sys.argv[0]])
    validate()
