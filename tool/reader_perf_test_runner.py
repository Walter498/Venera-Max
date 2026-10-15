#!/usr/bin/env python3
"""Reader work-count regressions; not a device FPS or memory benchmark."""
from pathlib import Path
import os
from comments_test_runner import execute
root=Path(os.environ['RUNNER_TEMP'])/'venera-comments-evidence'
root.mkdir(parents=True,exist_ok=True)
files=['test/continuous_reader_geometry_work_test.dart',
       'test/continuous_reader_navigation_test.dart',
       'test/continuous_reader_repivot_test.dart',
       'test/continuous_page_turn_coordinator_test.dart',
       'test/reader_local_page_read_test.dart',
       'test/reader_loading_initial_group_test.dart',
       'test/cached_image_loading_test.dart']
# Full comments discovery remains mandatory in the separate regression step.
import sys
mode = sys.argv[1] if len(sys.argv) > 1 else 'focused'
groups = {
    'focused': (files, 10),
    'lifetime': (['test/reader_image_lifetime_test.dart'], 8),
    'history': (['test/history_reader_queue_test.dart', 'test/reader_comment_cache_test.dart'], 11),
    'cache': (['test/cache_scan_index_test.dart', 'test/reader_cache_cleanup_test.dart'], 2),
    'hooks': (['test/reader_image_hook_lifetime_test.dart'], 1),
    'script': (['test/reader_script_image_lifetime_test.dart'], 1),
    'window': (['test/reader_long_session_window_test.dart'], 1),
    'stream': (['test/reader_image_prefetch_stream_test.dart', 'test/image_downloader_stream_test.dart'], 2),
}
files, minimum = groups[mode]
assert all(Path(p).is_file() for p in files), 'Missing required reader test'
raise SystemExit(0 if execute('reader-perf-' + mode, files, root, minimum=minimum) else 1)
