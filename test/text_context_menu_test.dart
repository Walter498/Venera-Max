import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:venera/components/components.dart';
import 'package:venera/utils/opencc.dart';
import 'package:venera/utils/translations.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(AppTranslation.init);

  test('OpenCC conversion is safe before its asset is initialized', () {
    expect(OpenCC.simplifiedToTraditional('监狱'), '监狱');
    expect(OpenCC.traditionalToSimplified('監獄'), '監獄');
    expect(OpenCC.hasChineseSimplified('监狱'), isFalse);
    expect(OpenCC.hasChineseTraditional('監獄'), isFalse);
  });

  testWidgets('fallback menu converts the selected text and keeps its range', (
    tester,
  ) async {
    // Widget tests do not have an iOS system context menu. Explicitly use
    // Android so this assertion remains a fallback-path test on every host.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await OpenCC.init();
    final controller = TextEditingController(text: '监狱');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            contextMenuBuilder: veneraTextContextMenuBuilder,
          ),
        ),
      ),
    );

    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 2);
    await tester.pump();
    final editable = tester.state<EditableTextState>(
      find.byType(EditableText),
    );
    final menu = veneraTextContextMenuBuilder(editable.context, editable);
    expect(menu, isA<AdaptiveTextSelectionToolbar>());
    final toolbar = menu as AdaptiveTextSelectionToolbar;
    final traditional = toolbar.buttonItems!.singleWhere(
      (item) => item.label == 'Traditional'.tl,
    );

    traditional.onPressed!();
    await tester.pump();

    expect(controller.text, '監獄');
    expect(controller.selection, const TextSelection(baseOffset: 0, extentOffset: 2));
    expect(tester.takeException(), isNull);
  });
}
