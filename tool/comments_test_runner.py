#!/usr/bin/env python3
"""Offline Flutter tests and real golden capture. Never turn failed compares green."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

BASELINE = '5290afd9ceeaeedda63ed54fff6b15a57c6c5674'  # same tree as local fa7afe19
GOLDENS = Path('test/goldens/comments')


def inspect_events(text, rc, minimum=1):
    events = []
    for line in text.splitlines():
        try:
            value = json.loads(line)
        except ValueError:
            continue
        if isinstance(value, dict) and 'type' in value:
            events.append(value)
    completed = [e for e in events if e['type'] == 'testDone' and not e.get('hidden', False)]
    failures = []
    if rc:
        failures.append(f'flutter exit {rc}')
    if any(e['type'] == 'testDone' and e.get('skipped') for e in events):
        failures.append('skipped tests are forbidden')
    if any(e['type'] == 'error' or (e['type'] == 'testDone' and e.get('result') != 'success') for e in events):
        failures.append('test error/failure event')
    if len(completed) < minimum:
        failures.append(f'completed {len(completed)} tests, require >= {minimum}')
    if not any(e['type'] == 'done' and e.get('success') is True for e in events):
        failures.append('no successful test runner done event')
    return dict(exit=rc, completed=len(completed), failures=failures)


def png_metadata(path):
    data = path.read_bytes()
    if data[:8] != b'\x89PNG\r\n\x1a\n' or data[12:16] != b'IHDR':
        raise ValueError(f'invalid PNG: {path}')
    offset, kinds, compressed = 8, [], bytearray()
    while offset < len(data):
        if offset + 12 > len(data):
            raise ValueError(f'truncated PNG: {path}')
        size = struct.unpack('>I', data[offset:offset + 4])[0]
        kind = data[offset + 4:offset + 8]
        end = offset + 8 + size
        if end + 4 > len(data):
            raise ValueError(f'truncated PNG chunk: {path}')
        payload = data[offset + 8:end]
        crc = struct.unpack('>I', data[end:end + 4])[0]
        if zlib.crc32(kind + payload) & 0xffffffff != crc:
            raise ValueError(f'PNG CRC mismatch: {path}')
        kinds.append(kind)
        if kind == b'IDAT':
            compressed.extend(payload)
        offset = end + 4
        if kind == b'IEND':
            break
    if not kinds or kinds[0] != b'IHDR' or kinds[-1] != b'IEND' or offset != len(data) or not compressed:
        raise ValueError(f'incomplete PNG: {path}')
    width, height = struct.unpack('>II', data[16:24])
    depth, color, method, filtering, interlaced = data[24:29]
    if depth != 8 or color not in (2, 6) or (method, filtering, interlaced) != (0, 0, 0):
        raise ValueError(f'unsupported renderer PNG format: {path}')
    pixels = zlib.decompress(compressed)
    channels = 4 if color == 6 else 3
    if len(pixels) != height * (1 + width * channels):
        raise ValueError(f'PNG decoded size mismatch: {path}')
    if (width, height) != (390, 844):
        raise ValueError(f'wrong fixed viewport: {path}: {width}x{height}')
    return dict(path=str(path), width=width, height=height,
                bytes=len(data), sha256=hashlib.sha256(data).hexdigest())


def execute(label, files, evidence, update=False, minimum=1):
    command = ['flutter', 'test', '--no-pub', '--reporter=json', '--concurrency=1',
               '--timeout=90s', *(['--update-goldens'] if update else []), *files]
    print('+', ' '.join(command), flush=True)
    # Suite-level GitHub timeout bounds native crashes/hangs as well.
    raw = evidence / f'{label}.jsonl'
    with raw.open('w') as output:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                   text=True, bufsize=1)
        for line in process.stdout:
            print(line, end='', flush=True)
            output.write(line)
        rc = process.wait()
    (evidence / f'{label}.exit').write_text(str(rc) + '\n')
    report = inspect_events(raw.read_text(), rc, minimum)
    report.update(command=command, files=files)
    (evidence / f'{label}.report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(label, json.dumps(report), flush=True)
    return not report['failures']


def discovered(pattern):
    # Root test/comments* only: no old target or source/live quota CLI.
    result = sorted(str(p) for p in Path('test').glob(pattern) if p.is_file())
    if not result:
        raise ValueError(f'zero new files for test/{pattern}; refusing skip')
    return result


def tests(evidence):
    names = subprocess.check_output(['git', 'ls-tree', '-r', '--name-only', BASELINE, 'test'], text=True).splitlines()
    authors = sorted(p for p in names if Path(p).match('test/*author*test.dart'))
    if not authors or not all(Path(p).is_file() for p in authors):
        raise ValueError('original author regression files missing')
    comments = discovered('comments*_test.dart')
    text = subprocess.check_output(['git', 'show', f'{BASELINE}:.github/workflows/ios-build.yml'], text=True)
    match = re.search(r'^\s*flutter test (.+?) 2>&1', text, re.M)
    if not match:
        raise ValueError('original regression command missing')
    original = match[1].split()
    if len(original) != 28 or len(set(original)) != 28 or not all(Path(p).is_file() for p in original):
        raise ValueError('original 28-file regression set changed/missing')
    manifest = dict(baseline=BASELINE, author_minimum=13, author=authors,
                    original_28=original, comments=comments)
    (evidence / 'tests-manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    results = [execute('author-original-13', authors, evidence, minimum=13),
               execute('original-28-files', original, evidence, minimum=28),
               execute('comments-new', comments, evidence)]
    return all(results)


def render(evidence):
    files = discovered('comments*golden*_test.dart')
    snapshots = evidence / 'screenshots'
    snapshots.mkdir(exist_ok=True)
    compare = execute('golden-compare', files, evidence)
    # Remove all inputs before capture: never publish an unchanged baseline as
    # though the current widgets rendered it. Restore inputs after archiving.
    with tempfile.TemporaryDirectory(prefix='comments-golden-input-') as temp:
        backup = Path(temp) / 'comments'
        existed = GOLDENS.exists()
        if existed:
            shutil.copytree(GOLDENS, backup)
            shutil.rmtree(GOLDENS)
        captured = False
        metadata = []
        validation = []
        try:
            captured = execute('golden-fresh-capture', files, evidence, update=True)
            generated = sorted(GOLDENS.rglob('*.png')) if GOLDENS.exists() else []
            for path in generated:
                relative = path.relative_to(GOLDENS)
                target = snapshots / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(path, target)
                try:
                    metadata.append(png_metadata(target))
                except ValueError as exc:
                    validation.append(str(exc))
            for theme in ('light', 'dark'):
                for scale in ('100', '200'):
                    if not any(p.name.endswith(f'_{theme}_{scale}.png') for p in generated):
                        validation.append(f'missing actual render: {theme} font {scale}%')
            if not generated:
                validation.append('zero fresh PNG files')
            report = dict(renderer='Flutter test widgets on pinned macOS SDK, not iOS device screenshot',
                          viewport=[390, 844], dpr=1, target_platform='iOS (test owner contract)',
                          compare_pass=compare, capture_pass=captured, pngs=metadata,
                          failures=validation,
                          approval='comparison failure remains failure; generated PNGs need human review')
            (evidence / 'render-report.json').write_text(json.dumps(report, indent=2) + '\n')
            print(json.dumps(report, indent=2), flush=True)
        finally:
            if GOLDENS.exists():
                shutil.rmtree(GOLDENS)
            if existed:
                shutil.copytree(backup, GOLDENS)
            # Flutter comparison failure output is also real renderer evidence.
            failures = Path('test/failures')
            if failures.exists():
                shutil.copytree(failures, evidence / 'golden-failures', dirs_exist_ok=True)
    return compare and captured and not validation


class SelfTests(unittest.TestCase):
    def test_zero_discovery(self):
        with tempfile.TemporaryDirectory() as tmp:
            previous = os.getcwd()
            try:
                os.chdir(tmp)
                with self.assertRaises(ValueError):
                    discovered('comments*_test.dart')
                Path('test').mkdir()
                Path('test/comments_fixture_test.dart').touch()
                self.assertEqual(discovered('comments*_test.dart'), ['test/comments_fixture_test.dart'])
                with self.assertRaises(ValueError):
                    discovered('comments*golden*_test.dart')
            finally:
                os.chdir(previous)

    def test_events_fail_closed(self):
        good = '\n'.join(json.dumps(x) for x in [dict(type='testDone', hidden=False,
            skipped=False, result='success'), dict(type='done', success=True)])
        self.assertFalse(inspect_events(good, 0)['failures'])
        for raw, rc, count in [('', 0, 1), (good, 1, 1), (good, 0, 13),
                              (good.replace('"skipped": false', '"skipped": true'), 0, 1),
                              (good.replace('"success": true', '"success": false'), 0, 1)]:
            self.assertTrue(inspect_events(raw, rc, count)['failures'])

    def test_png_dimensions(self):
        # Synthetic bytes are used ONLY in parser selftest, never screenshots.
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / 'parser-fixture.png'
            def chunk(kind, payload):
                return struct.pack('>I', len(payload)) + kind + payload + struct.pack('>I', zlib.crc32(kind + payload) & 0xffffffff)
            data = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 390, 844, 8, 6, 0, 0, 0))
            data += chunk(b'IDAT', zlib.compress(b'\0' * (844 * (1 + 390 * 4)))) + chunk(b'IEND', b'')
            path.write_bytes(data)
            self.assertEqual(png_metadata(path)['width'], 390)
            for broken in (b'not png', data[:-1], data[:24]):
                path.write_bytes(broken)
                with self.assertRaises(ValueError):
                    png_metadata(path)


if __name__ == '__main__':
    if sys.argv[1:] == ['--self-test']:
        unittest.main(argv=[sys.argv[0]])
    evidence = Path(os.environ['RUNNER_TEMP']) / 'venera-comments-evidence'
    evidence.mkdir(parents=True, exist_ok=True)
    try:
        ok = {'tests': tests, 'render': render}[sys.argv[1]](evidence)
    except Exception as exc:
        print(f'::error::Comments test/render gate: {exc}', flush=True)
        raise
    sys.exit(0 if ok else 1)
