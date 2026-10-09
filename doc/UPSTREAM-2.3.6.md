# Venera-Max 2.3.6+249

Upstream reference: [Kyosee/VeneraX v2.3.6](https://github.com/Kyosee/VeneraX/releases/tag/v2.3.6). The cumulative changes since v2.3.4 were reviewed because the previous fork version was 2.3.4+247.

## Ported

- v2.3.6: unique Home Hero identities per section/source/comic; task expansion states isolated from scroll storage and retained across filtering; completed upload transitions to empty/history without a type error.
- Task search, combined type/status filters, responsive cards and long confirmation actions.
- Custom comic cache directory (device-local, effective after restart), indexed startup scans, and waiting for startup cleanup before cache writes.
- Missing local cover reads now stop retrying permanently and cancelled reads release loading slots.
- PDF import as local comic images using PDFium; streamed EPUB exports for large books.
- Custom translation API scripts with example/test panel; scripts stay device-local. Existing missing-line detection and concurrency policy are retained.
- Separate AI Translation settings; setting inheritance/reset per device and per comic; settings search opens and highlights the target; sliders preview immediately and save on release.
- Local/WebDAV chapter modification-time metadata and favorite-folder long-name truncation.
- Simplified/Traditional Chinese translations and help for new features.

## Preserved customization

Custom home/source feed, category/search server filters, ShelfPage local/network/history tabs, immediate continue-reader entry, reading percentage, continuous scrolling speed, swipe distance, continuous chapter comments, per-comic cache clearing and custom translation concurrency remain in place.

## Deliberately excluded

- Upstream bulk chapter-order editor: this fork replaced the original chapter-order model and UI; importing it alone would produce an unconnected editor or change history/download indexing.
- Original favorites-sidebar search patch: this fork uses ShelfPage instead of those deleted upstream pages.
- Upstream release/AltStore metadata and source addresses: do not point fork updates at another repository's artifacts.

## Build and validation

Both iOS and Android must compile from the same commit. iOS regression workflow includes new tests for tasks, Home Hero, cache scanning/directory, cover loading, PDF/EPUB, scripts and settings navigation/scope/save. Passing CI verifies automated checks only; on-device verification of PDF rendering, custom cache directory access and translation scripts is separate.

Android manual builds now use Release optimization and R8; when a release key is absent, an explicit test-signing flag permits signing with the test certificate. Tagged production releases continue to require configured signing secrets.

Rollback branch: `backup/before-upstream-236` at `5f126d7`.
