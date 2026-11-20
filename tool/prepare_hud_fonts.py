import os
import pathlib
import subprocess

files = subprocess.check_output(['rg', '--files', '-uuu', '/System/Library/Fonts'], text=True).splitlines()
def pick(names):
    for name in names:
        for path in files:
            if pathlib.Path(path).name == name:
                return path
    raise SystemExit(f'Required native font unavailable: {names}')
latin = pick(['SFNS.ttf', 'SFNSDisplay.ttf', 'Helvetica.ttc'])
cjk = pick(['PingFang.ttc', 'STHeiti Light.ttc', 'STHeiti Medium.ttc'])
with open(os.environ['GITHUB_ENV'], 'a') as out:
    out.write(f'HUD_LATIN_FONT={latin}\nHUD_CJK_FONT={cjk}\nHUD_EVIDENCE=1\n')
print(f'Native HUD fonts: {latin}; {cjk}')
