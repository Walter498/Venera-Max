import 'dart:collection';
import 'package:flutter/foundation.dart' show debugPrintSynchronously;
import 'package:flutter_qjs/flutter_qjs.dart';

/// The locked bridge converts PROMISE_TRACK separately from the actual Future
/// rejection. These are observer-owned exports, not the callback result graph.
/// Preserve the original diagnostic; destroy only this observer's wrappers.
void reportUnhandledJsPromise(dynamic reason) {
  final refs = HashSet<JSRef>.identity();
  final visited = HashSet<Object>.identity();
  void collect(dynamic value) {
    if (value == null || !visited.add(value)) {
      return;
    }
    if (value is JSRef) {
      refs.add(value);
    }
    if (value is Map) {
      for (final entry in value.entries) {
        collect(entry.key);
        collect(entry.value);
      }
    } else if (value is List) {
      for (final child in value) {
        collect(child);
      }
    }
  }
  collect(reason);
  try {
    // Match the bridge's default output without retaining its native graph.
    debugPrintSynchronously('unhandled promise rejection: $reason');
  } finally {
    for (final ref in refs) {
      ref.destroy();
    }
  }
}
