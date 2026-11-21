# Vibe test acceptance matrix

Source base: `a9734d29435081a70480831ba5dc45bec0e89066`.
Installation: user explicitly chose overwrite. Bundle ID, App Group, URL schemes and data schema remain stable. Test build identity is applied only by the CI packaging script (3.0.0+3003, VeneraX Vibe).

## Required evidence (pending cloud execution)
| Area | Acceptance |
| --- | --- |
| Buttons | Readable custom fills; stable ready/loading geometry; one callback; keyboard focus; pointer cancel and scroll do not activate; real light/dark + 2x font captures |
| Segmented controls | Moving selection, RTL positioning, zero/single labels safe, semantics exactly once, reduced-motion snap |
| Home | Compact section radii/order retained; real HomePage, seeded local fixtures; edit/back works; narrow/large text |
| Favorites | Display-mode/scale retained; action reachability and long folder labels; real FavoritesPage/ShelfPage captures |
| Details | Same cover Hero tag and metadata; skeleton follows header breakpoints; return and back-to-top honor reduced motion |
| Overlays | Long content/action wrapping; keyboard safe area; dismissible/non-dismissible semantics; return result unchanged |
| Loading/toast/error | No extra backend delay/request; stable indicator bounds; no false percentage in accessible loading; full error readable; toast expiry/action retained |
| Reader | 17 independent 2.x HUD raster tests including defective build276 negative control; 8 complete Reader tests with real local PNGs |
| Existing behavior | Prior accepted regression suite plus directly affected pages/navigation/dialog tests |
| Comment UI | Existing golden files frozen; compare without regenerating |
| iOS package | Release compiler success, unsigned IPA CRC, Bundle ID/version/display name/architectures and SHA verification |

## Verification limits
Cloud widget raster tests render production Flutter widgets with real fonts and controlled local fixture data/plugin mocks. They do not establish physical-device performance, full native UITabBar rendering or successful live third-party services. The build is not installed on the device by the assistant.

No PASS is recorded in this document before a completed run and downloaded evidence. Final outcomes will be written to VIBE_TEST_VERIFICATION.md.
