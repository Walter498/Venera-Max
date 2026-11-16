#!/usr/bin/env bash
set -euo pipefail
# flutter test runs on the host, not inside an iOS app bundle. Explicitly
# prepare the same native libraries instead of skipping their regression tests.
qjs_path=$(python3 - <<'PY'
import json,pathlib,urllib.parse
cfg=pathlib.Path('.dart_tool/package_config.json').resolve()
packages=json.loads(cfg.read_text())['packages']
p=next(p for p in packages if p['name']=='flutter_qjs')
u=urllib.parse.urljoin(cfg.as_uri(),p['rootUri'])
print(urllib.parse.unquote(urllib.parse.urlparse(u).path))
PY
)
work="${RUNNER_TEMP:-/tmp}/venera-native-tests"
cmake -S "$qjs_path/test" -B "$work/qjs" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64
cmake --build "$work/qjs" --parallel 3
mkdir -p flutter_qjs.framework
cp "$work/qjs/libffiquickjs.dylib" flutter_qjs.framework/flutter_qjs
codesign --force --sign - flutter_qjs.framework/flutter_qjs
mkdir -p "$work/pdfium"
curl --fail --location --retry 2 \
  'https://github.com/bblanchon/pdfium-binaries/releases/download/chromium%2F7811/pdfium-mac-x64.tgz' \
  -o "$work/pdfium.tgz"
tar -xzf "$work/pdfium.tgz" -C "$work/pdfium"
pdfium="$work/pdfium/lib/libpdfium.dylib"
test -s "$pdfium"
if [ -n "${GITHUB_ENV:-}" ]; then
  printf 'PDFIUM_PATH=%s\n' "$pdfium" >> "$GITHUB_ENV"
fi
printf 'QuickJS + PDFium prepared for host tests\n'
