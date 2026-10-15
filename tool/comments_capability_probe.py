#!/usr/bin/env python3
"""Bounded native QuickJS probe. Never substitute for the full test gates."""
import os, pathlib, sys
from comments_test_runner import execute
root = pathlib.Path(os.environ['RUNNER_TEMP']) / 'venera-comments-evidence'
root.mkdir(exist_ok=True)
mode = sys.argv[1]
if mode == 'capability':
    ok = execute('qingman-capability-probe', ['test/comments_qingman_capability_test.dart'], root, minimum=6)
elif mode == 'shipped':
    ok = execute('qingman-shipped-source-probe', ['test/comments_qingman_shipped_source_test.dart'], root, minimum=8)
elif mode == 'recovery':
    ok = execute('qingman-recovery-probe', ['test/comments_provider_test.dart', 'test/comments_qingman_test.dart'], root, minimum=21)
elif mode == 'auto':
    ok = execute('qingman-auto-source-probe', ['test/comments_qingman_auto_source_test.dart'], root, minimum=6)
elif mode == 'matrix':
    ok = execute('comments-bridge-matrix-probe', ['test/comments_bridge_test.dart', '--plain-name', 'nullable capabilities and legacy reply matrix'], root, minimum=2)
else:
    raise SystemExit('unknown probe')
raise SystemExit(0 if ok else 1)
