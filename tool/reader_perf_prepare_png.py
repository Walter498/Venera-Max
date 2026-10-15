#!/usr/bin/env python3
"""Build the LOCKED plugin C source for macOS test host, not a replacement."""
import json, pathlib, subprocess, urllib.parse, hashlib, os
root=pathlib.Path.cwd()
packages=json.loads((root/'.dart_tool/package_config.json').read_text())['packages']
pkg=next(p for p in packages if p['name']=='lodepng_flutter')
u=urllib.parse.urlsplit(pkg['rootUri']);assert u.scheme=='file'
source=pathlib.Path(urllib.parse.unquote(u.path))/'src/lodepng.c'
assert source.is_file()
out=root/'lodepng_flutter.framework';out.mkdir(exist_ok=True)
lib=out/'lodepng_flutter'
subprocess.run(['xcrun','clang','-dynamiclib','-O2','-DDART_SHARED_LIB','-arch','x86_64',str(source),'-o',str(lib)],check=True)
subprocess.run(['codesign','--force','--sign','-',str(lib)],check=True)
report={'source':str(source),'source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'library_sha256':hashlib.sha256(lib.read_bytes()).hexdigest(),'kind':'original locked plugin macOS test host'}
p=pathlib.Path(os.environ['RUNNER_TEMP'])/'venera-comments-evidence/png-native-host.json';p.write_text(json.dumps(report,indent=2));print(json.dumps(report))
