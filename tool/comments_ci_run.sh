#!/usr/bin/env bash
set -euo pipefail
step=${1:?step required}
evidence="${RUNNER_TEMP:?}/venera-comments-evidence"
mkdir -p "$evidence"
exec > >(tee "$evidence/$step.log") 2>&1
finish() {
  rc=$?
  trap - EXIT
  printf 'step=%s exit=%s\n' "$step" "$rc" | tee "$evidence/$step.exit"
  if [[ "$rc" != 0 && -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    {
      printf '\n### Failed step: %s (exit %s)\n\n```text\n' "$step" "$rc"
      tail -n 100 "$evidence/$step.log"
      printf '\n```\n'
    } >> "$GITHUB_STEP_SUMMARY"
  fi
  exit "$rc"
}
trap finish EXIT
printf 'step=%s commit=%s platform=%s\n' "$step" "$(git rev-parse HEAD)" "$(uname -sm)"
case "$step" in
  init)
    test "${GITHUB_REF:-$(git symbolic-ref HEAD)}" = refs/heads/fix/comments-preview-four-20261014
    # Root verified remote 5290afd9 has exactly the local fa7afe19 tree.
    test "$(git rev-parse '5290afd9ceeaeedda63ed54fff6b15a57c6c5674^{tree}')" = b0a56c3a52b47ea79986eade62c90218e1e6f593
    git merge-base --is-ancestor 5290afd9ceeaeedda63ed54fff6b15a57c6c5674 HEAD
    git status --short
    python3 tool/comments_test_runner.py --self-test
    python3 tool/comments_validate_artifacts.py --self-test
    ;;
  outcomes)
    python3 - <<'PY'
import json, os, pathlib
p = pathlib.Path(os.environ['RUNNER_TEMP']) / 'venera-comments-evidence'
steps = json.loads(os.environ.get('COMMENTS_STEP_OUTCOMES', '{}'))
(p / 'workflow-outcomes.json').write_text(json.dumps(steps, indent=2) + '\n')
phases = {'evidence': 'init', 'dependencies': 'dependencies-ios', 'analyze': 'analyze',
          'native': 'native-tests', 'tests': 'tests', 'render': 'render', 'ios': 'ios'}
for name, result in steps.items():
    print(name, result.get('outcome'), result.get('conclusion'))
for name, phase in phases.items():
    path = p / (phase + '.exit')
    if not path.exists():
        # Never fabricate a process exit for a skipped/timeout/killed phase.
        path.write_text('step=' + phase + ' exit=UNAVAILABLE outcome=' +
                        steps.get(name, {}).get('outcome', 'not-recorded') + '\n')
PY
    ;;
  dependencies-ios)
    if [[ "$step" == dependencies-ios ]]; then
      sudo xcode-select --switch /Applications/Xcode_16.4.app
      xcodebuild -version
      xcrun --sdk iphoneos --show-sdk-version
      if ! command -v rg >/dev/null 2>&1; then
        brew install ripgrep
      fi
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
    baseline_commit=5290afd9ceeaeedda63ed54fff6b15a57c6c5674
    baseline_root=$(mktemp -d "${RUNNER_TEMP}/venera-comments-baseline.XXXXXX")
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
  tests|render)
    python3 tool/comments_test_runner.py "$step"
    ;;
  ios)
    export CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
    flutter build ios --release --no-codesign --no-pub -v
    python3 tool/comments_validate_artifacts.py
    ;;
  *) printf 'Unknown step: %s\n' "$step"; exit 2 ;;
esac
git diff --exit-code -- pubspec.yaml pubspec.lock rust-toolchain.toml ios/Podfile ios/Runner.xcodeproj/project.pbxproj android/app/build.gradle
