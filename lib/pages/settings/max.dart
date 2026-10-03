import 'package:flutter/material.dart';
import 'package:venera/components/components.dart';
import 'package:venera/pages/settings/reader.dart';
import 'package:venera/utils/translations.dart';

/// Convenience index for our added features. Original settings stay in place;
/// this page only provides a second, compact entry point.
class MaxSettings extends StatelessWidget {
  const MaxSettings({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: Appbar(title: Text('Max'.tl), style: AppbarStyle.shadow),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.translate_rounded),
            title: Text('AI translation'.tl),
            subtitle: Text('Whole-chapter translation, progress and performance controls'.tl),
            onTap: () => context.to(() => const ReaderSettings()),
          ),
          ListTile(
            leading: const Icon(Icons.swipe_up_rounded),
            title: Text('Chapter swipe distance'.tl),
            subtitle: Text('Adjust the distance for next/previous chapter gestures'.tl),
            onTap: () => context.to(() => const ReaderSettings()),
          ),
          ListTile(
            leading: const Icon(Icons.filter_alt_outlined),
            title: Text('Source-native filters'.tl),
            subtitle: Text('Search and category filters follow each source protocol'.tl),
          ),
        ],
      ),
    );
  }
}
