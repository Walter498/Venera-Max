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
       'test/cached_image_loading_test.dart',
       'test/comments_reader_integration_test.dart',
       'test/comments_reader_footer_test.dart',
       'test/comments_sort_preference_test.dart']
assert all(Path(p).is_file() for p in files),'Missing required reader test'
raise SystemExit(0 if execute('reader-perf-focused',files,root,minimum=10) else 1)
