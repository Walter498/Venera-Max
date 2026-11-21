# Venera Vibe Test — 2026-11-21

## Goal
Deliver an installable unsigned iOS test IPA based on accepted `a9734d29435081a70480831ba5dc45bec0e89066` (`rebuild/base-first-venera-300`), inspired by https://vibedesign.tips/. Branch `test/vibe-polish-20261121`. Keep stable branch untouched; no release publication, no device installation. Current task owner: this session only.

## Installation choice (explicit user selection)
User chose **overwrite existing app** in the installation card. Preserve `io.github.kyosee.venera`, App Group, URL schemes and all storage paths. Package 3.0.0+3003 with display name `VeneraX Vibe`. No installation is performed here. Keep accepted stable artifact/branch available for rollback; no schema migration.

## Design intent
A cohesive broad pass, not a marketing skin: restrained press depth, coherent entrance/exit/move motion, nested radius geometry, stable loading, clearer home/favorites/detail hierarchy and overlays. Maintain compact home square sections and the accepted 2.x reader HUD. Keep existing information, all actions, data/backend behavior, tab identifiers, selection and sorting contracts. Dark/light and reduced motion; text scaling, safe areas and accessibility. No new dependencies. Web examples inform principles, not identical Apple Liquid Glass claims.

## Frozen areas
No edits to lib/pages/reader/**, ios native tab implementation, network/auth/source/parser/data/database schemas, comments rendering/golden baselines, translations semantics. Do not change reader gestures, accepted HUD typography/stroke/battery/chrome, home section order/settings or favorite display mode. Do not modify test assertions to conceal regressions.

## Parallel ownership
- Agent A: lib/components/ios_design.dart and lib/components/button.dart; new test/vibe_controls_test.dart. Shared API guaranteed: `VeneraMotion.reduce(BuildContext context)`, `VeneraMotion.duration(BuildContext context, Duration value)`, curves `VeneraMotion.enter`, `.exit`, `.move`. Preserve existing public APIs. Optional reusable passive press-feedback widget must not consume callbacks or long presses. No other production files.
- Agent B: lib/pages/home_page.dart, lib/pages/home_source_feed.dart, lib/pages/favorites/shelf_page.dart, lib/pages/favorites/folder_widgets.dart, lib/pages/favorites/favorites_page.dart, lib/pages/comic_details_page/comic_page.dart; new tests beginning `test/vibe_pages_`. Do not alter business state, persistence or part files. Must include production-page rendered capture fixtures where feasible.
- Agent C: lib/components/loading.dart, lib/components/message.dart, lib/components/flyout.dart, lib/components/pop_up_widget.dart, lib/components/side_bar.dart; new tests beginning `test/vibe_states_`. No backend load-state flow changes or extra network requests; loading polish presentation only.
- Main: CI, version/build identity, independent review/testing, final integration, artifact verification. Other files only after explicit ownership coordination.

Shared working tree, disjoint file ownership. Agents never commit/push/start CI; main integrates. Read current file before edits. Read relevant existing tests and skill ui-polish. Report exact files/change rationale/new tests and any unverified assumptions. Local Flutter is absent; actual Flutter tests run in GitHub Actions, not substitute syntax claims.

## Gates
1. Review diff and no frozen-area changes.
2. New production-widget interaction/layout tests, light/dark/large type/reduced motion screenshots.
3. Existing 245 regression suite plus 17 HUD render/8 full Reader integration tests; add directly affected tests as feasible.
4. Flutter iOS release compile --no-codesign; version/Bundle ID metadata and ZIP/hash validation.
5. Download evidence and visually inspect; capture limits clearly (widget raster is not device install/performance).
6. Direct IPA link and concise tested/unverified report, no claimed success until verified.
