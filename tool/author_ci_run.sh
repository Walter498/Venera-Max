#!/usr/bin/env bash
set -euo pipefail
step=${1:?step required}
evidence="${RUNNER_TEMP:?}/venera-author-evidence"
mkdir -p "$evidence"
exec > >(tee "$evidence/$step.log") 2>&1
finish() {
  rc=$?
  trap - EXIT
  printf 'step=%s exit=%s\n' "$step" "$rc" | tee "$evidence/$step.exit"
  exit "$rc"
}
trap finish EXIT
printf 'step=%s commit=%s platform=%s\n' "$step" "$(git rev-parse HEAD)" "$(uname -sm)"
case "$step" in
  dependencies-ios|dependencies-android)
    if [[ "$step" == dependencies-ios ]]; then
      sudo xcode-select --switch /Applications/Xcode_16.4.app
      xcodebuild -version
      xcrun --sdk iphoneos --show-sdk-version
    fi
    # Read the original toolchain; fail if it differs from the approved pin.
    rust_version=$(python3 -c 'import pathlib,re; print(re.search(r"channel\s*=\s*\"([^\"]+)\"", pathlib.Path("rust-toolchain.toml").read_text())[1])')
    test "$rust_version" = 1.85.1
    rustup toolchain install "$rust_version" --profile minimal
    rustup show
    flutter --version
    flutter pub get --enforce-lockfile
    git diff --exit-code -- pubspec.yaml pubspec.lock rust-toolchain.toml
    ;;
  analyze)
    # Capture both runs; analyzer's diagnostic exit is data, setup failures are not.
    current_root=$(pwd -P)
    baseline_commit=27476af2
    baseline_root=$(mktemp -d "${RUNNER_TEMP}/venera-author-baseline.XXXXXX")
    # RUNNER_TEMP is ephemeral; retain baseline files only in evidence logs.
    current_raw="$evidence/analyzer-current.machine"
    baseline_raw="$evidence/analyzer-baseline.machine"
    package_config="$current_root/.dart_tool/package_config.json"
    test -s "$package_config"
    cp "$package_config" "$evidence/package_config.current.json"
    printf 'baseline_commit=%s\ncurrent_root=%s\nbaseline_root=%s\nresolved_package_config_sha256=' "$baseline_commit" "$current_root" "$baseline_root" | tee "$evidence/analyzer-provenance.txt"
    shasum -a 256 "$package_config" | tee -a "$evidence/analyzer-provenance.txt"
    git archive "$baseline_commit" | tar -x -C "$baseline_root"
    cp "$current_root/pubspec.lock" "$evidence/pubspec.current.before.lock"
    cp "$baseline_root/pubspec.lock" "$evidence/pubspec.baseline.before.lock"
    python3 tool/author_analyzer_compare.py --self-test
    python3 tool/author_analyzer_compare.py --remap-config "$package_config" \
      --current-root "$current_root" --baseline-root "$baseline_root" \
      --report "$evidence/package_config.mapping.json"
    cp "$baseline_root/.dart_tool/package_config.json" "$evidence/package_config.baseline.json"
    # Use the Dart SDK bundled with the selected Flutter; Dart analyze never runs pub get.
    flutter_bin=$(command -v flutter)
    dart_bin=$(python3 -c 'import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve().parent / "cache/dart-sdk/bin/dart")' "$flutter_bin")
    test -x "$dart_bin"
    "$dart_bin" --version | tee -a "$evidence/analyzer-provenance.txt"
    printf 'dart_bin=%s\n' "$dart_bin" | tee -a "$evidence/analyzer-provenance.txt"
    (cd "$current_root" && set +e; "$dart_bin" analyze --format=machine > "$current_raw" 2>&1; printf '%s' "$?" > "$evidence/analyzer-current.exit")
    (cd "$baseline_root" && set +e; "$dart_bin" analyze --format=machine > "$baseline_raw" 2>&1; printf '%s' "$?" > "$evidence/analyzer-baseline.exit")
    current_exit=$(cat "$evidence/analyzer-current.exit")
    baseline_exit=$(cat "$evidence/analyzer-baseline.exit")
    set +e
    python3 tool/author_analyzer_compare.py \
      --current "$current_raw" --baseline "$baseline_raw" \
      --current-root "$current_root" --baseline-root "$baseline_root" \
      --current-exit "$current_exit" --baseline-exit "$baseline_exit" \
      --report "$evidence/analyzer-comparison.json"
    compare_rc=$?
    set -e
    if [[ "$compare_rc" != 0 ]]; then
      python3 - "$evidence/analyzer-comparison.json" <<'PY'
import json,sys
report=json.load(open(sys.argv[1]))
for message in report.get('failures', []):
    print('::error title=Analyzer gate::'+message.replace('%','%25').replace('\n','%0A').replace('\r','%0D'))
for item in report.get('new_diagnostics', [])[:30]:
    print('::error file='+item['file']+'::'+item['code']+' '+item['message'].replace('%','%25').replace('\n','%0A').replace('\r','%0D'))
PY
    fi
    printf 'analyzer_exit current=%s baseline=%s\n' "$current_exit" "$baseline_exit" | tee -a "$evidence/analyzer-provenance.txt"
    cmp "$current_root/pubspec.lock" "$evidence/pubspec.current.before.lock"
    cmp "$baseline_root/pubspec.lock" "$evidence/pubspec.baseline.before.lock"
    exit "$compare_rc"
    ;;
  native-tests)
    bash tool/prepare_native_tests.sh
    ;;
  tests)
    mapfile_compat=()
    while IFS= read -r file; do mapfile_compat+=("$file"); done < <(rg --files test -g '*author*test.dart' | sort)
    test "${#mapfile_compat[@]}" -gt 0
    printf 'Author test: %s\n' "${mapfile_compat[@]}"
    flutter test --no-pub "${mapfile_compat[@]}"
    # Keep the exact original regression set, with no expanded legacy suite.
    python3 - <<'PY'
import pathlib,re,subprocess,sys
text=pathlib.Path('.github/workflows/ios-build.yml').read_text()
command=re.search(r'^\s*flutter test (.+?) 2>&1',text,re.M)[1]
files=command.split()
assert len(files)==28 and all(pathlib.Path(p).is_file() for p in files)
print('Original regression files:', ' '.join(files),flush=True)
sys.exit(subprocess.run(['flutter','test','--no-pub',*files]).returncode)
PY
    ;;
  ios)
    export CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
    flutter build ios --release --no-codesign --no-pub -v
    python3 tool/author_validate_artifacts.py ios
    ;;
  android)
    test "${VENERA_TEST_SIGNING:-}" = 1
    test ! -e android/key.properties
    mkdir -p "$HOME/.android"
    if [[ ! -s "$HOME/.android/debug.keystore" ]]; then
      keytool -genkeypair -keystore "$HOME/.android/debug.keystore" \
        -storepass android -keypass android -alias androiddebugkey \
        -dname 'CN=Android Debug,O=Android,C=US' -keyalg RSA -keysize 2048 -validity 10000
    fi
    keytool -list -keystore "$HOME/.android/debug.keystore" -storepass android -alias androiddebugkey
    flutter build apk --release --no-pub -v
    python3 tool/author_validate_artifacts.py android
    ;;
  *) printf 'Unknown step: %s\n' "$step"; exit 2 ;;
esac
git diff --exit-code -- pubspec.yaml pubspec.lock rust-toolchain.toml ios/Podfile ios/Runner.xcodeproj/project.pbxproj android/app/build.gradle
