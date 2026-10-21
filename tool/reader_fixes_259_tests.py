from pathlib import Path
import os, sys
from comments_test_runner import execute
root = Path(os.environ['RUNNER_TEMP']) / 'venera-comments-evidence'
root.mkdir(parents=True, exist_ok=True)
mode = sys.argv[1] if len(sys.argv) > 1 else 'targeted'
groups = {
  'targeted': ['test/back_gesture_multitouch_test.dart', 'test/chapter_metadata_test.dart', 'test/chapter_card_layout_test.dart', 'test/reader_navigation_pending_comments_test.dart'],
  'regression': ['test/back_gesture_buried_route_test.dart', 'test/home_edit_back_gesture_test.dart', 'test/comments_reader_footer_test.dart', 'test/comments_reader_integration_test.dart', 'test/continuous_reader_navigation_test.dart', 'test/continuous_reader_repivot_test.dart', 'test/continuous_reader_geometry_work_test.dart', 'test/reader_long_session_window_test.dart', 'test/comic_details_cache_test.dart', 'test/comments_effective_provider_test.dart', 'test/reader_local_page_read_test.dart'],
}
files = groups[mode]
assert all(Path(p).is_file() for p in files)
raise SystemExit(0 if execute('reader-fixes-259-' + mode, files, root, minimum=19 if mode == 'targeted' else 15) else 1)
