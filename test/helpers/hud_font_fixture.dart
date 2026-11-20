import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// CI screenshots require actual Apple fonts. Missing fonts fail evidence
/// generation rather than silently producing Ahem placeholder rectangles.
Future<void> loadHudTestFonts() async {
  final icons = FontLoader('MaterialIcons')
    ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
  await icons.load();
  final paths = {
    'HudLatin': Platform.environment['HUD_LATIN_FONT'],
    'HudCJK': Platform.environment['HUD_CJK_FONT'],
  };
  for (final entry in paths.entries) {
    if (entry.value == null || !File(entry.value!).existsSync()) {
      if (Platform.environment['HUD_EVIDENCE'] == '1') {
        throw StateError('Missing real font: ${entry.key}');
      }
      continue;
    }
    final data = ByteData.sublistView(await File(entry.value!).readAsBytes());
    await (FontLoader(entry.key)..addFont(Future.value(data))).load();
  }
}
