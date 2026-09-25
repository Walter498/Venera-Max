# Venera-Max

> A comic reader forked from [VeneraX](https://github.com/Kyosee/VeneraX) (itself a fork of
> [venera-app/venera](https://github.com/venera-app/venera)) and **heavily customized to our own
> reading habits**. Everything in this repo is our own work — what we added and what we fixed is
> documented here, in our own words.
>
> Full (Chinese) version with the complete changelog: [README.md](README.md)

- Platform: iOS (main target), Android and desktop kept from upstream
- Primary comic source: **栗子漫画 / lizimh** — see [Walter498/Walter](https://github.com/Walter498/Walter)
- Build: push to `main` → GitHub Actions workflow `venerax-ios` (~12 min) → grab the IPA from the run's **Artifacts**

## What we added

- **Chapter panel**: list / cover-preview modes, a real collapse (3 rows + "show all (N)"), lazy chapter covers, asc/desc order, duplicate filtering
- **Reader**: seamless multi-chapter continuous mode; **swipe up/down to change chapter** with an adjustable distance (40–400 px) and a progress ring; **haptic feedback** (medium impact on switching, light click when the prompt appears); single-tap toolbar summon gated by a real 800 ms stillness check; custom tap zones; edge-only back gesture; auto reading (smooth scroll / animated page turns); chapter picker for downloads; inline chapter comments; 15 s load watchdog
- **Home / explore / search**: inline 首页·更新·排行 tabs, source-provided home feed, cross-source merges, filter chips, aggregated same-name search sorted by real chapter count
- **Details**: last-read time + previous 3 reading positions, collection cover/chapter view toggle, per-comic cache clearing, inline comments
- **Favorites**: shelf layout (favorites / lists / footprints) with folders and multiple sort modes
- **Appearance**: Material 3 / Liquid Glass switch
- **Downloads**: multi-select, failed page no longer stalls the task, consistent User-Agent
- **Source (lizimh)**: host pool with automatic fallback + line speed test, official image order via the `chapter/v3` API (JWT only), faster page-count probing, detection of the first existing page, no page dropping on probe failure
- **Settings**: numeric sliders for all reading knobs, per-comic and per-device settings, settings search

## What we fixed (symptom → cause → fix)

| Symptom | Cause | Fix |
|---|---|---|
| Huge blank under the chapter grid in cover-preview mode | `childCount` was the full chapter count; "collapsed" cells only returned an empty widget but **still took up space** | Collapsed mode is now a `Wrap` of fixed-size cells inside a height-capped sliver — physically 3 rows |
| No "show all" button in cover-preview mode | Button was gated behind `if (!gridMode)` | Rendered in both modes, with the cover-grid's own 15-cell threshold |
| First tap after opening a comic did nothing | The programmatic initial scroll (and later layout shifts while images load) fired `ScrollEnd`, stamping "just stopped scrolling" → the 800 ms guard swallowed the tap | Only a **user drag** counts as scrolling |
| No vibration when swiping to the next/previous chapter | It was never implemented | `mediumImpact` when crossing the threshold, `selectionClick` when the prompt appears |
| Wrong page count (156 → 153) and scrambled order | The probe deleted pages that failed once → everything after shifted | Only two consecutive missing pages end the chapter; failures never delete pages |
| A chapter stuck on "1/N" forever | The chapter does not start at page 1 (pages 1–4 are 404) | Find the first existing page and start the list there |
| Image order differed from the official app | Uploaded chapters' filenames are not the reading order | Use the official `pics` array, fall back to numeric order |
| Everything failed after `ai.qsmm.fun` died | Hard-coded host | Host pool with fallback, remembered host, speed test |
| Blank chapter covers | JS bridge lacked `chapterCovers`; `Image.network` got 403 | Field added; covers use the app image loader (with UA) |
| Crashes: rank top-3 badge, details page, deleted local folder | `colors[-1]`, mutating a shared list, unguarded path listing | Fixed each with a guard/copy |
| Download task stalled by one bad page | No skip-on-failure | Skip and continue |
| "Clear cache" left stale source data | HTTP response cache untouched | Cleared too, plus a per-comic cache button |
| Reader spinning forever | No timeout | 15 s watchdog with error + retry |

## License

GPL-3.0, inherited from upstream. The lizimh source is for personal use only.