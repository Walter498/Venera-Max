#!/usr/bin/env bash
set -euo pipefail
phase=${1:?phase required}
test "${GITHUB_REF:?}" = refs/heads/fix/reader-comments-auto-258
evidence="${RUNNER_TEMP:?}/venera-comments-evidence"
mkdir -p "$evidence"
case "$phase" in
 init)
  git merge-base --is-ancestor 5290afd9ceeaeedda63ed54fff6b15a57c6c5674 HEAD
  python3 tool/comments_test_runner.py --self-test
  python3 tool/reader_perf_validate_artifacts.py --self-test
  printf '{"commit":"%s","kind":"reader performance candidate","release_accepted":false}\n' "$GITHUB_SHA" > "$evidence/reader-provenance.json"
  ;;
 dependencies-ios|analyze)
  bash tool/comments_ci_run.sh "$phase"
  ;;
 native-tests)
  bash tool/comments_ci_run.sh native-tests
  python3 tool/reader_perf_prepare_png.py
  ;;
 metadata|effective-provider|focused|lifetime|history|window|stream|cache|hooks|script)
  python3 tool/reader_perf_test_runner.py "$phase"
  ;;
 regression)
  bash tool/comments_ci_run.sh tests
  ;;
 ios)
  export CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=''
  set -o pipefail
  flutter build ios --release --no-codesign --no-pub -v 2>&1 | tee "$evidence/reader-ios.log"
  python3 tool/reader_perf_validate_artifacts.py
  ;;
 *) echo "Unknown phase: $phase"; exit 2;;
esac
git diff --exit-code -- pubspec.yaml pubspec.lock rust-toolchain.toml ios/Podfile ios/Runner.xcodeproj/project.pbxproj
