#!/usr/bin/env python3
"""Run independent test gates and retain every result, even after a failed gate."""
from pathlib import Path
import json, os, re, subprocess, sys, time

ROOT = Path(__file__).resolve().parents[1]
os.chdir(ROOT)
EVIDENCE = ROOT / 'build/vibe-evidence'
EVIDENCE.mkdir(parents=True, exist_ok=True)
env = dict(os.environ, HUD_EVIDENCE='1', VIBE_EVIDENCE='1')
legacy = re.search(r'flutter test (.+?) 2>&1', (ROOT / '.github/workflows/reader-hud-acceptance.yml').read_text().split('name: Existing regression suite')[1]).group(1).split()
new = subprocess.check_output(['rg', '--files', 'test', '-g', 'vibe*_test.dart'], text=True).splitlines()
assert new, 'New UI tests must exist before a candidate can pass'
affected = '''test/app_search_field_test.dart test/menu_button_test.dart test/context_menu_test.dart test/pop_up_scaffold_bottom_inset_test.dart test/favorites_page_layout_test.dart test/favorites_dialog_test.dart test/favorites_folder_restore_test.dart test/shelf_navigation_regression_test.dart test/home_edit_back_gesture_test.dart test/home_reading_statistics_entry_test.dart test/translated_comics_home_test.dart test/comic_detail_cover_provider_test.dart test/navigation_bar_labels_test.dart test/reader_auto_page_turning_button_test.dart test/reader_night_mode_button_test.dart test/reading_widget_test.dart test/sync_config_qr_widget_test.dart'''.split()
groups = {
    'new-ui': sorted(new),
    'reader-pixel': ['test/reader_hud_render_test.dart'],
    'reader-integration': ['test/reader_hud_integration_test.dart'],
    'stable-regression': legacy,
    'affected-regression': [p for p in affected if p not in legacy],
    'frozen-comments-golden': ['test/comments_ui_golden_test.dart', 'test/comments_footer_golden_test.dart', 'test/comments_rich_golden_test.dart'],
}
results = {}
for group, tests in groups.items():
    print(f'\n=== {group} ({len(tests)} files) ===', flush=True)
    started = time.monotonic()
    command = ['flutter', 'test', '--reporter', 'expanded', '--concurrency=2', '--timeout=2m', *tests]
    with (EVIDENCE / f'{group}.log').open('w') as log:
        process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, env=env)
        for line in process.stdout:
            print(line, end='', flush=True)
            log.write(line)
        code = process.wait()
    text = (EVIDENCE / f'{group}.log').read_text()
    counts = [int(v) for v in re.findall(r'\+(\d+)', text)]
    results[group] = {'exit_code': code, 'passed_counter': max(counts, default=0), 'seconds': round(time.monotonic() - started, 2), 'files': tests}
    (EVIDENCE / 'test-results.json').write_text(json.dumps(results, indent=2))
    print(f'GATE {group}: {code}', flush=True)
print(json.dumps(results, indent=2))
sys.exit(1 if any(r['exit_code'] for r in results.values()) else 0)
