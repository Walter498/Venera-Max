from pathlib import Path
import subprocess
root=Path('/var/minis/workspace/Venera-3.0.0-custom')

def replace_first(path, old, new):
 p=root/path; s=p.read_text(); n=s.count(old)
 if n != 1: raise RuntimeError(f'{path}: expected 1, got {n}')
 p.write_text(s.replace(old,new,1))

replace_first('lib/foundation/app.dart', "      }\n    }\n    }\n    if (isAndroid) {", "      }\n    }\n    if (isAndroid) {")
replace_first('lib/foundation/comic_source/comic_source.dart', "      return;\n    }\n    }\n    if (_haveWaitingTask) return;", "      return;\n    }\n    if (_haveWaitingTask) return;")
replace_first('lib/pages/settings/settings_page.dart', "part 'translation_languages_settings.dart';\npart 'translation_models_settings.dart';\npart 'llm_providers_settings.dart';\npart 'translation_script_settings.dart';\npart 'translation_prompt_settings.dart';\npart 'translation_languages_settings.dart';", "part 'translation_languages_settings.dart';\npart 'translation_models_settings.dart';\npart 'llm_providers_settings.dart';\npart 'translation_script_settings.dart';\npart 'translation_prompt_settings.dart';")

# Use the coherent upstream bottom-bar function; the earlier merge selected one
# half of each side and left two local Widget child declarations.
p=root/'lib/pages/reader/scaffold.dart'; s=p.read_text()
start=s.index('  Widget buildBottom() {')
end=s.index('  void toggleNightMode() {', start)
up=subprocess.check_output(['git','show','synthetic/upstream-v3.0.0-walter-base:lib/pages/reader/scaffold.dart'],cwd=root,text=True)
u0=up.index('  Widget buildBottom() {'); u1=up.index('  void toggleNightMode() {',u0)
s=s[:start]+up[u0:u1]+s[end:]
p.write_text(s)

# Keep the first (newer _id-based) collection helpers and the single chapter
# builder; remove duplicate lower helpers created by the unrelated merge.
p=root/'lib/pages/comic_details_page/comic_page.dart'; s=p.read_text()
show=s.index('  void showComments() {')
start=s.index('\n  void _onCollectionChanged()', show)
end=s.index('\n  Widget buildChapters()', start)
s=s[:start]+s[end:]
start=s.index('\n  Widget _buildCollectionCovers()', s.index('  Widget buildChapters()'))
end=s.index('\n  Widget buildThumbnails()', start)
s=s[:start]+s[end:]
p.write_text(s)

# The upstream model registry is the coherent 3.0 implementation; the merge
# had left the old PP-OCRv5 declaration in front of it.
p=root/'lib/foundation/image_translation/translation_models.dart'
up=subprocess.check_output(['git','show','synthetic/upstream-v3.0.0-walter-base:lib/foundation/image_translation/translation_models.dart'],cwd=root,text=True)
p.write_text(up)
print('repaired')
