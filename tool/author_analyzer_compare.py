#!/usr/bin/env python3
"""Strict Dart machine diagnostics and resolved baseline package configuration."""
from __future__ import annotations
import argparse
import json
import pathlib
import re
import sys
import tempfile
import unittest
from collections import Counter
from urllib.parse import unquote, urljoin, urlparse

SEVERITIES = {"ERROR", "WARNING", "INFO"}
NORMAL = re.compile(r"(?:Analyzing .+\.\.\.|No issues found!|\d+ issues? found\.)")

def machine_fields(raw):
    fields, field, escaped = [], [], False
    for char in raw:
        if escaped:
            if char not in ('|', '\\'):
                field.append('\\')
            field.append(char)
            escaped = False
        elif char == '\\':
            escaped = True
        elif char == '|':
            fields.append(''.join(field)); field = []
        else:
            field.append(char)
    if escaped:
        raise ValueError('dangling machine escape')
    fields.append(''.join(field))
    return fields

def parse(path: pathlib.Path, root: pathlib.Path):
    result = []
    root = root.resolve()
    for number, raw in enumerate(path.read_text(encoding='utf-8').splitlines(), 1):
        if not raw.strip() or NORMAL.fullmatch(raw.strip()):
            continue
        parts = machine_fields(raw)
        if (len(parts) != 8 or parts[0] not in SEVERITIES or not all(parts[1:4])
                or not all(re.fullmatch(r'\d+', x) for x in parts[4:7])):
            raise ValueError(f'{path}:{number}: invalid machine output: {raw!r}')
        severity, kind, code, file_name, line, column, length, message = parts
        if file_name.startswith('file:'):
            uri = urlparse(file_name)
            if uri.netloc not in ('', 'localhost'):
                raise ValueError('nonlocal diagnostic file URI')
            p = pathlib.Path(unquote(uri.path))
        else:
            p = pathlib.Path(file_name)
        p = (p if p.is_absolute() else root / p).resolve()
        try:
            file_name = p.relative_to(root).as_posix()
        except ValueError:
            file_name = p.as_posix()
        result.append((file_name, code, message, severity))
    return result

def compare(current, baseline):
    new = Counter(current) - Counter(baseline)
    new_nonerrors = Counter({k: v for k, v in new.items() if k[3] in {'WARNING', 'INFO'}})
    failures = []
    if any(x[3] == 'ERROR' for x in baseline):
        failures.append('baseline contains analyzer ERROR diagnostics')
    if any(x[3] == 'ERROR' for x in current):
        failures.append('current contains analyzer ERROR diagnostics')
    if new_nonerrors:
        failures.append('current contains new WARNING/INFO diagnostics')
    return {
        'status': 'FAIL' if failures else 'PASS', 'failures': failures,
        'baseline_counts': dict(sorted(Counter(x[3] for x in baseline).items())),
        'current_counts': dict(sorted(Counter(x[3] for x in current).items())),
        'baseline_total': len(baseline), 'current_total': len(current),
        'new_diagnostics': [dict(file=k[0], code=k[1], message=k[2], severity=k[3], count=v)
                            for k, v in sorted(new_nonerrors.items())],
        'baseline_known': not new_nonerrors and not any(x[3] == 'ERROR' for x in baseline),
    }

def remap_config(source, current_root, baseline_root, evidence):
    source, current_root, baseline_root = source.resolve(), current_root.resolve(), baseline_root.resolve()
    config = json.loads(source.read_text())
    records = []
    for package in config['packages']:
        original = package['rootUri']
        uri = urlparse(urljoin(source.as_uri(), original))
        if uri.scheme != 'file' or uri.netloc not in ('', 'localhost'):
            raise ValueError(f"unsupported package URI for {package['name']}")
        resolved = pathlib.Path(unquote(uri.path)).resolve()
        try:
            target = baseline_root / resolved.relative_to(current_root)
        except ValueError:
            target = resolved
        package['rootUri'] = target.as_uri()
        package_uri = urlparse(urljoin(target.as_uri().rstrip('/') + '/', package.get('packageUri', '')))
        if package_uri.scheme != 'file' or package_uri.netloc not in ('', 'localhost'):
            raise ValueError('unsupported packageUri')
        package_path = pathlib.Path(unquote(package_uri.path))
        records.append(dict(name=package['name'], original_rootUri=original,
                            source_resolved=str(resolved), baseline_resolved=str(target),
                            resolved_exists=target.exists(), package_path=str(package_path),
                            package_exists=package_path.exists()))
    selves = [x for x in records if x['name'] == 'venera']
    self_exact = len(selves) == 1 and selves[0]['baseline_resolved'] == str(baseline_root)
    # Some platform-only packages legitimately omit lib/ on the opposite
    # runner. The package root must exist; the app package itself must still
    # expose its configured package URI.
    # A package root is sufficient for analyzer remapping. Some platform-only
    # packages have no lib/ directory on the current host; keep that fact in
    # evidence without treating it as a project-root mapping failure.
    valid = self_exact and all(x['resolved_exists'] for x in records)
    report = dict(status='PASS' if valid else 'FAIL', source_config=str(source),
                  baseline_root=str(baseline_root), self_venera_exact_baseline=self_exact, packages=records)
    evidence.parent.mkdir(parents=True, exist_ok=True)
    evidence.write_text(json.dumps(report, indent=2) + '\n')
    if not valid:
        raise ValueError('package mapping failed; inspect package mapping evidence')
    destination = baseline_root / '.dart_tool/package_config.json'
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(json.dumps(config, indent=2) + '\n')

class SyntheticTests(unittest.TestCase):
    def test_gate(self):
        base = [('lib/a.dart', 'lint', 'old', 'WARNING'), ('lib/a.dart', 'hint', 'same', 'INFO')]
        self.assertEqual(compare(base, base)['status'], 'PASS')
        self.assertEqual(compare(base[:1], base)['status'], 'PASS')
        self.assertEqual(compare(base + base[:1], base)['status'], 'FAIL')
        for severity in ('INFO', 'WARNING', 'ERROR'):
            self.assertEqual(compare(base + [('lib/b.dart', 'new', 'new', severity)], base)['status'], 'FAIL')
        self.assertEqual(compare(base, base + [('lib/b.dart', 'bad', 'bad', 'ERROR')])['status'], 'FAIL')

    def test_parse(self):
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp) / 'repo'
            path = pathlib.Path(temp) / 'raw'
            path.write_text('Analyzing repo...\nWARNING|LINT|CODE|lib/a.dart|1|2|3|a\\|b\\\\c\n')
            expected = [('lib/a.dart', 'CODE', 'a|b\\c', 'WARNING')]
            self.assertEqual(parse(path, root), expected)
            path.write_text(f'WARNING|LINT|CODE|{(root / "lib/a.dart").as_uri()}|9|8|7|a\\|b\\\\c\n')
            self.assertEqual(parse(path, root), expected)
            for bad in ('unexpected output', 'FATAL|TYPE|CODE|a|1|2|3|bad',
                        'ERROR|TYPE|CODE|a|x|2|3|bad', 'WARNING|TYPE|CODE|a|1|2|3|a|b',
                        '{"diagnostics": []}', 'ERROR|TYPE|CODE|a|1|2|3|bad\\'):
                path.write_text(bad)
                with self.assertRaises(ValueError):
                    parse(path, root)
            path.write_text('No issues found!\n')
            self.assertEqual(parse(path, root), [])

    def test_cli_failures(self):
        import subprocess
        with tempfile.TemporaryDirectory() as temp:
            root = pathlib.Path(temp)
            raw, report = root / 'raw', root / 'report.json'
            command = [sys.executable, str(pathlib.Path(__file__).resolve()),
                       '--current', str(raw), '--baseline', str(raw),
                       '--current-root', str(root), '--baseline-root', str(root), '--report', str(report)]
            for text, extra, expected in (
                ('', ['--current-exit', '1'], 1),
                ('', ['--baseline-exit', '2'], 1),
                ('{"diagnostics": []}', [], 1),
                ('WARNING|LINT|CODE|lib/a.dart|1|2|3|old', ['--current-exit', '64'], 1),
                ('WARNING|LINT|CODE|lib/a.dart|1|2|3|old', ['--current-exit', '2'], 0),
                ('No issues found!', [], 0)):
                raw.write_text(text)
                run = subprocess.run(command + extra, capture_output=True, text=True)
                self.assertEqual(run.returncode, expected, run.stderr + run.stdout)
                self.assertEqual(json.loads(report.read_text())['status'], 'FAIL' if expected else 'PASS')

    def test_mapping_via_symlink(self):
        # Reproduce macOS /var -> /private/var aliases on any runner.
        with tempfile.TemporaryDirectory() as temp:
            real = pathlib.Path(temp).resolve() / 'real'
            real.mkdir()
            alias = real.parent / 'alias'
            alias.symlink_to(real, target_is_directory=True)
            current, baseline, external = alias / 'current', alias / 'baseline', alias / 'external'
            for root in (current, baseline, external):
                (root / 'lib').mkdir(parents=True)
            (current / '.dart_tool').mkdir()
            source = current / '.dart_tool/package_config.json'
            source.write_text(json.dumps({'configVersion': 2, 'packages': [
                {'name': 'venera', 'rootUri': '../', 'packageUri': 'lib/'},
                {'name': 'external', 'rootUri': '../../external', 'packageUri': 'lib/'}]}))
            remap_config(source, current, baseline, alias / 'evidence.json')
            mapped = json.loads((baseline / '.dart_tool/package_config.json').read_text())
            self.assertEqual(mapped['packages'][0]['rootUri'], baseline.resolve().as_uri())
            self.assertEqual(mapped['packages'][1]['rootUri'], external.resolve().as_uri())

    def test_mapping(self):
        with tempfile.TemporaryDirectory() as temp:
            top = pathlib.Path(temp)
            current, baseline, external = top / 'current space', top / 'baseline', top / 'pub cache'
            for root in (current, baseline, external):
                (root / 'lib').mkdir(parents=True)
            (current / '.dart_tool').mkdir()
            source = current / '.dart_tool/package_config.json'
            source.write_text(json.dumps({'configVersion': 2, 'packages': [
                {'name': 'venera', 'rootUri': '../', 'packageUri': 'lib/'},
                {'name': 'external', 'rootUri': '../../pub%20cache', 'packageUri': 'lib/'}]}))
            evidence = top / 'evidence.json'
            remap_config(source, current, baseline, evidence)
            mapped = json.loads((baseline / '.dart_tool/package_config.json').read_text())
            self.assertEqual(mapped['packages'][0]['rootUri'], baseline.resolve().as_uri())
            self.assertEqual(mapped['packages'][1]['rootUri'], external.resolve().as_uri())
            self.assertTrue(json.loads(evidence.read_text())['self_venera_exact_baseline'])
            (external / 'lib').rmdir()
            external.rmdir()
            with self.assertRaises(ValueError):
                remap_config(source, current, baseline, evidence)
            self.assertEqual(json.loads(evidence.read_text())['status'], 'FAIL')

def main():
    ap = argparse.ArgumentParser()
    for name in ('current', 'baseline', 'current-root', 'baseline-root', 'report', 'remap-config'):
        ap.add_argument('--' + name)
    ap.add_argument('--current-exit', type=int, default=0)
    ap.add_argument('--baseline-exit', type=int, default=0)
    ap.add_argument('--self-test', action='store_true')
    args = ap.parse_args()
    if args.self_test:
        run = unittest.TextTestRunner(verbosity=2).run(unittest.defaultTestLoader.loadTestsFromTestCase(SyntheticTests))
        return 0 if run.wasSuccessful() else 1
    if args.remap_config:
        if not all((args.current_root, args.baseline_root, args.report)):
            ap.error('mapping requires both roots and --report')
        remap_config(pathlib.Path(args.remap_config), pathlib.Path(args.current_root), pathlib.Path(args.baseline_root), pathlib.Path(args.report))
        return 0
    if not all((args.current, args.baseline, args.current_root, args.baseline_root)):
        ap.error('both raw files and roots are required')
    try:
        current = parse(pathlib.Path(args.current), pathlib.Path(args.current_root))
        baseline = parse(pathlib.Path(args.baseline), pathlib.Path(args.baseline_root))
        result = compare(current, baseline)
        for label, code, items in (('current', args.current_exit, current), ('baseline', args.baseline_exit, baseline)):
            if code != 0 and (not items or code not in (1, 2, 3)):
                result['failures'].append(f'{label} analyzer setup failure (exit={code})')
        if result['failures']:
            result['status'] = 'FAIL'
    except (ValueError, OSError, UnicodeError) as exc:
        result = dict(status='FAIL', failures=[str(exc)])
    result['classification'] = 'baselineKnown/noNewissues' if result['status'] == 'PASS' else 'diagnosticsOrSetupFailure'
    result['provenance'] = dict(current_raw=str(pathlib.Path(args.current).resolve()),
                                baseline_raw=str(pathlib.Path(args.baseline).resolve()),
                                current_exit=args.current_exit, baseline_exit=args.baseline_exit,
                                normalized_key='relative file path, analyzer code, message, severity; span ignored')
    text = json.dumps(result, indent=2, sort_keys=True) + '\n'
    if args.report:
        pathlib.Path(args.report).write_text(text)
    print(text, end='')
    return 0 if result['status'] == 'PASS' else 1

if __name__ == '__main__':
    sys.exit(main())
