# Reader HUD 2.x restoration — verified 2026-11-20

## Scope and cause

Only the resting reader information bar is changed. Build 276 drew the chapter/page outline at 14pt, then inherited the new 16pt / 1.35 global body style for the fill. These were two different glyph layouts, reproducing the submitted ghosting screenshot. Clock/percentage outlines and the battery icon outline had also been removed.

`ReaderHudText` now derives both paint passes from one complete, non-inheriting 2.x style: 14pt, w400, height 1.43, letter spacing .25, stroke 1.4. The platform font family, locale and text scaling are shared. Fill uses onSurface and outline uses onInverseSurface. Clock and percentage use this same component; the 16pt battery icon has its original eight 0.8px non-blurred outline shadows. The common footer retains bottom 13 and side 25 insets; the left label is constrained to prevent collisions with the status information.

Business APIs, page-turning, gesture thresholds, home UI, toolbar materials and auto-scroll behavior are unchanged.

## Acceptance evidence

- Source commit: `bc2286b94eaab8ff6d2665fe90ed2593f8d93410`
- Successful GitHub Actions: https://github.com/Walter498/Venera-Max/actions/runs/44658168263
- Test host: macOS 15, Flutter 3.44.3, actual SFNS + STHeiti fonts (not Ahem placeholders).
- 17 rendering/geometry/semantics tests pass.
  - Six rendered 1290×315 reference comparisons: light/dark themes × white/black/red background.
  - Reference is frozen 2.x scaffold code from `cbdf3c56` under its original Material 3 typography, independent of the replacement widget.
  - Each comparison has **0 differing pixels** under matching font/theme conditions.
  - Negative controls reproduce build276's mixed-size text and fail parity.
  - Stroke/fill origins, widths, heights and baselines match at 100%, 150%, 200% text scale and 80/240/600 logical-pixel constraints.
  - Page changes replace both glyph layers, and accessibility exposes a single label.
- Eight full production Reader scenarios pass: 390×844 and 430×932, light/dark themes, 100% battery / 35% charging.
  - Actual LocalComic files, production file:// IO adapter, decoder, Reader, scaffold, theme and gestures.
  - 32 actual Flutter-rendered screenshots, not HTML redraws.
  - Real key page turns, center taps opening/closing chrome, and chapter changes.
  - iPhone safe-area fixtures top59/bottom34; asserted HUD stays outside the open control card.
  - HUD settings-dependent visibility checked by changing settings and rebuilding the scaffold; this is not settings-panel tap automation.
- Existing regression suite: 245 passed.
- Total: **270 tests passed**.
- iOS release build: successful, code signing disabled.
- Downloaded images independently compared again with Pillow; all six reference pairs remain pixel-identical. The 16 open/closed footer crops were visually reviewed.

## Artifact

`VeneraX-reader-hud-2x.ipa`

- Version: 3.0.0, bundle build 3002
- Bundle ID: io.github.kyosee.venera
- Minimum iOS: 15.1
- SHA256: `5c417a259cfa5a874172fabf8acfcc1352c36b1acbe168fdbe41a03e099ba41d`
- Matches CI SHA256.txt; ZIP CRC passes.

This is the accepted artifact from the source commit above. Any following documentation-only commit does not change its code. No new public release was automatically generated during acceptance.

## Verification boundary

Screenshots are actual Flutter rendering on the macOS test host with real fonts and iPhone layout fixtures. Device plugins (clock/battery environment) are controlled test inputs. They are not screenshots from the user's physical iPhone or an installed iOS Simulator build. Physical-device installation was not performed; no such claim is made.
