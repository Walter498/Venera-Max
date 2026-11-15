from pathlib import Path
import subprocess
root=Path('/var/minis/workspace/Venera-3.0.0-custom')
choices={
 '.github/workflows/main.yml':'ours',
 'assets/init.js':'ours',
 'lib/components/comic.dart':'theirs',
 'lib/foundation/appdata.dart':'ours',
 'lib/foundation/app_page_route.dart':'ours',
 'lib/foundation/comic_details_cache.dart':'ours',
 'lib/foundation/image_translation/llm_translator.dart':'ours',
 'lib/foundation/image_translation/translation_models.dart':'theirs',
 'lib/foundation/image_translation/translation_worker.dart':'ours',
 'lib/network/images.dart':'ours',
 'lib/pages/comic_details_page/chapters.dart':'ours',
 'lib/pages/comic_details_page/comic_page.dart':'ours',
 'lib/pages/favorites/shelf_page.dart':'theirs',
 'lib/pages/reader/chapter_comments.dart':'ours',
 'lib/pages/reader/comic_image.dart':'ours',
 'lib/pages/reader/images.dart':'theirs',
 'lib/pages/reader/reader.dart':'theirs',
 'lib/pages/reader/scaffold.dart':'ours',
 'lib/pages/reader/shader_image.dart':'ours',
 'lib/pages/search_result_page.dart':'ours',
 'lib/pages/settings/image_enhance_preview.dart':'ours',
 'lib/pages/settings/reader.dart':'theirs',
 'lib/pages/settings/translation_languages_settings.dart':'theirs',
 'pubspec.yaml':'theirs',
}
for fn,mode in choices.items():
    p=root/fn
    if not p.exists():
        continue
    lines=p.read_text(errors='replace').splitlines(keepends=True)
    out=[]; i=0
    while i<len(lines):
        if lines[i].startswith('<<<<<<<'):
            left=[]; right=[]; i+=1; target=left
            while i<len(lines) and not lines[i].startswith('>>>>>>>'):
                if lines[i].startswith('======='):
                    target=right
                else:
                    target.append(lines[i])
                i+=1
            if i>=len(lines): raise RuntimeError(f'unclosed {fn}')
            out.extend(left if mode=='ours' else right)
            i+=1
        else:
            out.append(lines[i]); i+=1
    p.write_text(''.join(out))
print('resolved',len(choices),'files')
