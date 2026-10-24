part of 'settings_page.dart';

/// 管理官方2.3.7支持的自定义翻译目标语言。
class TranslationLanguagesPage extends StatefulWidget {
  const TranslationLanguagesPage({super.key});

  @override
  State<TranslationLanguagesPage> createState() => _TranslationLanguagesPageState();
}

class _TranslationLanguagesPageState extends State<TranslationLanguagesPage> {
  Future<void> _edit([CustomTargetLanguage? existing]) async {
    final code = TextEditingController(text: existing?.code ?? '');
    final name = TextEditingController(text: existing?.name ?? '');
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(existing == null ? '添加目标语言'.tl : '编辑目标语言'.tl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: name, decoration: InputDecoration(labelText: '名称'.tl)),
            TextField(
              controller: code,
              enabled: existing == null,
              decoration: InputDecoration(
                labelText: '语言代码'.tl,
                hintText: '例如 th、pt-BR',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: Text('取消'.tl)),
          FilledButton(
            onPressed: () {
              final normalized = TranslationTargets.normalizeCode(code.text);
              final label = name.text.trim();
              if (normalized == null || label.isEmpty ||
                  (existing == null && TranslationTargets.isTaken(normalized))) {
                return;
              }
              TranslationTargets.save(CustomTargetLanguage(code: normalized, name: label));
              Navigator.pop(dialogContext, true);
            },
            child: Text('保存'.tl),
          ),
        ],
      ),
    );
    code.dispose();
    name.dispose();
    if (result == true && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final custom = TranslationTargets.custom;
    return Scaffold(
      appBar: Appbar(
        title: Text('自定义语言'.tl),
        actions: [IconButton(onPressed: () => _edit(), icon: const Icon(Icons.add))],
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text('内置目标语言'.tl),
            subtitle: Text(TranslationTargets.builtIn.values.map((e) => e.label).join('、')),
          ),
          for (final language in custom)
            ListTile(
              title: Text(language.name),
              subtitle: Text(language.code),
              onTap: () => _edit(language),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () {
                  TranslationTargets.remove(language.code);
                  setState(() {});
                },
              ),
            ),
          if (custom.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('可添加内置列表之外的翻译目标语言。'.tl),
            ),
        ],
      ),
    );
  }
}
