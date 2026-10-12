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
    # Evidence is outside the checkout; never copy pubspec or suppress diagnostics.
    flutter analyze --no-pub --fatal-infos --fatal-warnings
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
