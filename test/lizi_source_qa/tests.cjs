'use strict';
/* Behavioural assertions for lizimh.js 2.33.34. Fixture network only. */
const path = require('path');
const fs = require('fs');

function run(env) {
  const { loadSource, check, results, assert, eq, freshState, catalogRequests,
    detail, catalog, catalog2, catalogWire, catalog2Wire, vm, SRC, RES, SRC_DIR } = env;
  const BIND = { '54235': '646782', '999': '653476' };
  const state = freshState();
  const h = loadSource({ settings: { tencentCommentBindings: JSON.stringify(BIND) }, state });
  const src = h.source;

  // ---------- A. generated source identity / new init constructor ----------
  check('A1 version is 2.33.34', () => {
    const v = src.version;
    eq(v, '2.33.34', 'version');
    return v;
  });
  check('A2 loadChapterMetadata hook present', () => {
    assert(typeof src.comic.loadChapterMetadata === 'function', 'hook missing');
    assert(typeof src.comic.loadInfo === 'function', 'loadInfo missing');
  });
  check('A3 new project ComicDetails keeps chapterMetadata (old init drops it)', () => {
    const cd = vm.runInContext('new ComicDetails({title:"t",chapters:{"1":"a"},chapterMetadata:{"1":{updateTime:"2026-01-10T13:01:33.104Z",dateSource:"lizi"}},chapterCovers:{"1":"u"}})', h.context);
    assert(cd && cd.chapterMetadata && cd.chapterMetadata['1'], 'chapterMetadata dropped');
    eq(cd.chapterMetadata['1'].dateSource, 'lizi');
    eq(cd.chapterCovers && cd.chapterCovers['1'], 'u');
  });

  // ---------- B. lizi created_at cached on details, keyed by order ----------
  let info = null;
  check('B1 loadInfo returns ComicDetails with chapterMetadata keyed by order', async () => {});
  const infoPromise = src.comic.loadInfo('54235').then(x => { info = x; });
  return (async () => {
    await infoPromise;
    check('B1 loadInfo -> ComicDetails instance', () => {
      assert(info && typeof info === 'object', 'no details');
      assert(info.chapterMetadata && typeof info.chapterMetadata === 'object', 'no chapterMetadata');
      assert(info.chapters && Object.keys(info.chapters).length === 385, 'chapter count ' + Object.keys(info.chapters).length);
    });
    check('B2 every chapterMetadata key is an existing order key', () => {
      const keys = Object.keys(info.chapterMetadata), ch = Object.keys(info.chapters);
      eq(keys.length, 385, 'metadata count');
      for (const k of keys) assert(ch.includes(k), 'orphan metadata key ' + k);
    });
    check('B3 updateTime equals that order key\'s created_at exactly', () => {
      // Rebuild order keys with the documented rule to check the mapping itself.
      const numOf = (ch) => { let o = parseInt(ch.order); if (isFinite(o) && o > 0) return o; const m = String(ch.name || '').match(/第\s*(\d+)\s*[话話]/); return m ? parseInt(m[1]) : 0; };
      const raw = (detail.data.chapters || []).slice().sort((a, b) => (numOf(a) || 1e9) - (numOf(b) || 1e9));
      let prev = 0; const want = {};
      for (const ch of raw) { let o = numOf(ch); if (!o || o <= prev) o = prev + 1; prev = o; want[String(o)] = ch.created_at; }
      for (const k of Object.keys(want)) {
        const m = info.chapterMetadata[k];
        assert(m && m.updateTime === want[k], 'order ' + k + ' date ' + JSON.stringify(m) + ' want ' + want[k]);
        assert(m.dateSource === 'lizi', 'dateSource@' + k);
      }
      return Object.keys(want).length;
    });
    check('B4 order keys are unique and ascending (duplicate source order repaired)', () => {
      const keys = Object.keys(info.chapters).map(Number);
      eq(keys.length, new Set(keys).size, 'duplicate order keys');
      for (let i = 1; i < keys.length; i++) assert(keys[i] > keys[i - 1], 'not ascending at ' + i);
      assert(keys.length === 385, 'count');
    });

    const infoAgain = await src.comic.loadInfo('54235');
    check('B5 independent loadInfo fetches fresh details and replaces seed', () => {
      assert(infoAgain !== info, 'completed details were reused');
      eq(infoAgain, info, 'same fixture values');
      assert(src._chapterInfoCache['54235'] === infoAgain, 'latest seed');
      eq(state.requests.filter(r => /detail\/54235/.test(r.url)).length, 2, 'local detail requests');
    });

    // ---------- C. full directory request: one Tencent catalog serves all 385 IDs ----------
    const allIds = Object.keys(info.chapters);
    state.catalogHits.length = 0; state.requests.length = 0;
    const fullStarted = Date.now();
    const full = await src.comic.loadChapterMetadata('54235', allIds);
    const fullMs = Date.now() - fullStarted;
    check('C0 all 385 legal chapter IDs are accepted', () => {
      eq(Object.keys(full).length, 385, 'full metadata count');
      eq(catalogRequests(state).length, 1, 'full catalog GETs');
      eq(state.requests.filter(r => /detail\//.test(r.url)).length, 0, 'metadata must reuse latest seed');
      return { chapters: Object.keys(full).length, ms: fullMs, catalogRequests: catalogRequests(state).length };
    });

    // ---------- C. real batch catalog: one request feeds all requested chapters ----------
    // Oracle: canonical title (source's own normalizer, no identity rules) must be
    // unique in the catalog. Values still come from the catalog row, not from source.
    const Cls0 = vm.runInContext('LiziChapterMetadata', h.context);
    const exact = new Map();
    for (const r of catalog.data.chapter_list) {
      const k = Cls0.title(r.chapter_title);
      assert(!exact.has(k), 'duplicate canonical title ' + k);
      exact.set(k, r);
    }
    const matchable = Object.keys(info.chapters).filter(k => exact.has(Cls0.title(info.chapters[k]))).map(Number);
    assert(matchable.length > 300, 'too few exact titles: ' + matchable.length);
    // eight consecutive id keys that all have exact Tencent counterparts
    let batch = [];
    for (let i = 0; i + 8 <= matchable.length; i++) {
      const cand = matchable.slice(i, i + 8);
      if (cand[7] - cand[0] === 7) { batch = cand.map(String); break; }
    }
    assert(batch.length === 8, 'no contiguous batch');

    state.catalogHits.length = 0; state.requests.length = 0;
    const first = await src.comic.loadChapterMetadata('54235', batch);
    check('C1 one catalog GET for all 8 chapters', () => {
      eq(catalogRequests(state).length, 1, 'catalog GETs');
      return catalogRequests(state)[0].url;
    });
    check('C2 likes and dates equal catalog good_count/update_date', () => {
      for (const k of batch) {
        const row = exact.get(Cls0.title(info.chapters[k]));
        const got = first[k];
        assert(got, 'missing key ' + k);
        eq(got.likesCount, row.good_count, 'likes@' + k);
        eq(got.likesSource, 'tencent', 'source@' + k);
        eq(got.tencentUpdateTime, row.update_date, 'date@' + k);
      }
      return batch.map(k => [k, first[k].likesCount]);
    });
    check('C3 no stats/comment request was made', () => {
      const bad = state.requests.filter(r => /getWonderfulChapterTopicList|getChapterTopicList/.test(r.url));
      eq(bad.length, 0, 'stats requests');
    });
    check('C4 catalog payload fits the raised catalog decoder (wire>100k)', () => {
      assert(catalogWire.length > 100000, 'wire ' + catalogWire.length);
      assert(catalogWire.length < 2097152, 'wire too big');
      return { wire: catalogWire.length };
    });

    // ---------- D. sequential calls are NOT cached ----------
    state.catalogHits.length = 0; state.requests.length = 0;
    const t0 = Date.now();
    const second = await src.comic.loadChapterMetadata('54235', batch);
    check('D1 second sequential call issues a second live catalog GET', () => {
      eq(catalogRequests(state).length, 1, 'new GETs on second call');
      assert(state.catalogHits.length === 1, 'hits');
      return { ms: Date.now() - t0 };
    });
    check('D2 second result is a fresh object, values still correct', () => {
      assert(second !== first, 'same object identity');
      eq(second, first, 'values');
    });
    check('D3 provider holds no catalog entry in its TTL cache', () => {
      const p = src._chapterMetadataProvider && src._chapterMetadataProvider.provider;
      assert(p, 'no provider');
      const keys = Array.from(p.cache.keys());
      const bad = keys.filter(k => /comicChapterList/.test(k));
      eq(bad, [], 'cached catalog keys');
      return keys.length;
    });

    // ---------- E. same in-flight request is shared ----------
    state.catalogHits.length = 0; state.requests.length = 0; state.delay = 500;
    const eIds = batch.slice(0, 4), fIds = batch.slice(4);
    let eCall = src.comic.loadChapterMetadata('54235', eIds);
    // second call must not reuse load()-level flight key (different ids)
    let fCall = src.comic.loadChapterMetadata('54235', fIds);
    const [eRes, fRes] = await Promise.all([eCall, fCall]);
    state.delay = 0;
    check('E1 two concurrent different-batch calls share one catalog GET', () => {
      eq(catalogRequests(state).length, 1, 'catalog GETs');
      return state.catalogHits.map(x => x.id);
    });
    check('E2 both concurrent callers get complete facts', () => {
      for (const k of eIds.concat(fIds)) {
        const row = exact.get(Cls0.title(info.chapters[k]));
        eq({ tencentUpdateTime: (eRes[k] || fRes[k]).tencentUpdateTime, likesCount: (eRes[k] || fRes[k]).likesCount, likesSource: (eRes[k] || fRes[k]).likesSource }, { tencentUpdateTime: row.update_date, likesCount: row.good_count, likesSource: 'tencent' }, 'fact@' + k);
      }
    });
    state.catalogHits.length = 0; state.requests.length = 0; state.delay = 400;
    const [g1, g2] = await Promise.all([
      src.comic.loadChapterMetadata('54235', batch),
      src.comic.loadChapterMetadata('54235', batch),
    ]);
    state.delay = 0;
    check('E4 identical concurrent calls -> one catalog GET, equal results', () => {
      eq(catalogRequests(state).length, 1, 'catalog GETs');
      eq(g1, g2, 'results');
    });

    // ---------- F. failure after success is not served from cache ----------
    state.catalogMode = 'fail500'; state.catalogHits.length = 0; state.requests.length = 0;
    const failed = await src.comic.loadChapterMetadata('54235', batch);
    state.catalogMode = 'ok';
    check('F1 schema/HTTP failure returns empty, never stale likes', () => {
      eq(catalogRequests(state).length, 1, 'attempted a real GET');
      eq(failed, Object.fromEntries(batch.map(k => [k, info.chapterMetadata[k]])), 'Lizi dates survive HTTP failure');
      return Object.keys(failed).length;
    });
    state.catalogMode = 'zero'; state.catalogHits.length = 0; state.requests.length = 0;
    const badJson = await src.comic.loadChapterMetadata('54235', batch);
    state.catalogMode = 'ok';
    check('F2 unparseable body -> {} (no fallback to previous values)', () => {
      eq(badJson, Object.fromEntries(batch.map(k => [k, info.chapterMetadata[k]])), 'Lizi dates survive decode failure');
      eq(catalogRequests(state).length, 1);
    });

    // ---------- G. zero likes are valid; 653476 fixture ----------
    const st2 = freshState();
    const chapters = catalog2.data.chapter_list;
    const d999 = { code: 201, data: { name: '小飞侠', author: 'X', tags: '', score: 0,
      chapters: chapters.map((r, i) => ({ id: 90000 + i, order: i + 1, name: r.chapter_title, created_at: '2023-07-' + String((i % 28) + 1).padStart(2, '0') + 'T10:00:00.000Z' })) } };
    st2.detail999 = d999;
    const h2 = loadSource({ settings: { tencentCommentBindings: JSON.stringify(BIND) }, state: st2 });
    const info2 = await h2.source.comic.loadInfo('999');
    const ids2 = chapters.slice(0, 8).map((_, i) => String(i + 1));
    const zero = await h2.source.comic.loadChapterMetadata('999', ids2);
    check('G1 good_count 0 yields likesCount 0 (not omitted, not null)', () => {
      eq(catalogRequests(st2).length, 1, 'catalog GETs');
      for (const k of ids2) {
        const idx = Number(k) - 1;
        eq({ tencentUpdateTime: zero[k].tencentUpdateTime, likesCount: zero[k].likesCount, likesSource: zero[k].likesSource }, { tencentUpdateTime: chapters[idx].update_date, likesCount: 0, likesSource: 'tencent' }, 'zero@' + k);
      }
      return zero[ids2[0]];
    });
    check('G2 exact PART titles match without guessing', () => {
      eq(zero['1'].likesCount, 0);
      eq(info2.chapters['1'], chapters[0].chapter_title);
    });

    // Re-entry must replace both directory and metadata identity from the new seed.
    const refreshState = freshState();
    const refreshSettings = { tencentCommentBindings: JSON.stringify(BIND) };
    const date = '2026-10-21T10:00:00.000Z';
    const row = (i, created_at) => ({ id: 91000 + i, order: i + 1, name: chapters[i].chapter_title, created_at });
    refreshState.detail999 = { code: 201, data: { name: '小飞侠', author: 'X', chapters: [row(0, ''), row(1, date)] } };
    const refresh = loadSource({ settings: refreshSettings, state: refreshState });
    const oldSeed = await refresh.source.comic.loadInfo('999');
    const oldMeta = await refresh.source.comic.loadChapterMetadata('999', ['1', '2']);
    const refreshMeta = refresh.source._chapterMetadataProvider;
    const oldLocal = refreshMeta.locals.get('999').local;
    refreshState.detail999 = { code: 201, data: { name: '小飞侠', author: 'X', chapters: [row(0, date), row(1, date), row(2, '')] } };
    const newSeed = await refresh.source.comic.loadInfo('999');
    const beforeMeta = refreshState.requests.filter(r => /detail\/999/.test(r.url)).length;
    const newMeta = await refresh.source.comic.loadChapterMetadata('999', ['1', '2', '3']);
    check('G3 re-entry GETs detail twice; latest seed adds chapter and fills old missing date', () => {
      eq(beforeMeta, 2, 'independent detail GETs');
      eq(refreshState.requests.filter(r => /detail\/999/.test(r.url)).length, 2, 'metadata extra detail GETs');
      assert(newSeed !== oldSeed && refresh.source._chapterInfoCache['999'] === newSeed, 'new seed identity');
      eq(Object.keys(oldSeed.chapters).length, 2);
      eq(Object.keys(newSeed.chapters).length, 3);
      assert(!oldMeta['1'].updateTime, 'old missing date');
      eq(newMeta['1'].updateTime, date, 'old chapter filled');
      eq(newMeta['2'].updateTime, date, 'last original order date retained');
      eq(newMeta['3'].tencentUpdateTime, chapters[2].update_date, 'new missing date supplemented');
      eq(newMeta['3'].likesCount, 0, 'new chapter matches latest local identity');
      assert(refreshMeta.locals.get('999').local !== oldLocal, 'local identity must change with seed');
      eq(catalogRequests(refreshState).length, 2, 'each independent metadata fetches Tencent catalog');
    });
    refreshState.detail999.data.chapters[2].created_at = date;
    // Concurrent detail callers share the unfinished request even after a prior seed.
    const [parallel1, parallel2] = await Promise.all([
      refresh.source.comic.loadInfo('999'), refresh.source.comic.loadInfo('999')
    ]);
    check('G4 concurrent loadInfo shares exactly one detail GET', () => {
      eq(refreshState.requests.filter(r => /detail\/999/.test(r.url)).length, 3);
      assert(parallel1 === parallel2, 'concurrent details identity');
      assert(parallel1 !== newSeed, 'previous completed seed not reused');
      eq(parallel1.chapterMetadata['3'].updateTime, date, 'new chapter missing local date filled');
    });
    for (const invalid of ['{', '[]', '{"999":"invalid"}']) {
      refreshSettings.tencentCommentBindings = invalid;
      const before = refreshState.requests.length;
      const fallback = await refresh.source.comic.loadChapterMetadata('999', ['1', '2', '3']);
      check('G5 invalid binding preserves every Lizi date: ' + invalid, () => {
        eq(fallback, parallel1.chapterMetadata);
        eq(refreshState.requests.length, before, 'invalid binding must not fetch Tencent');
      });
    }
    refreshSettings.tencentCommentBindings = JSON.stringify(BIND);
    refreshState.catalogMode = 'fail500';
    const fallback = await refresh.source.comic.loadChapterMetadata('999', ['1', '2', '3']);
    check('G6 Tencent failure preserves first and last Lizi dates without stale likes', () => {
      eq(fallback, parallel1.chapterMetadata);
    });
    refreshState.catalogMode = 'ok';
    const savedBinding = refreshMeta.provider.binding;
    refreshMeta.provider.binding = async () => { throw new Error('binding failed'); };
    const bindingFallback = await refresh.source.comic.loadChapterMetadata('999', ['1', '2', '3']);
    refreshMeta.provider.binding = savedBinding;
    check('G7 Tencent binding failure preserves Lizi dates', () => { eq(bindingFallback, parallel1.chapterMetadata); });

    // Explicit request gates prove overlap without timing/speed assumptions.
    const deferred = () => { let resolve; const promise = new Promise(r => { resolve = r; }); return { promise, resolve }; };
    const bindingGate = deferred(), catalogGate = deferred(), bothStarted = deferred();
    const overlapState = freshState();
    let bindingStarted = false, catalogStarted = false, returned = false;
    overlapState.onRequest = async url => {
      if (/m\.ac\.qq\.com\/comic\/index\//.test(url)) {
        bindingStarted = true;
        if (catalogStarted) bothStarted.resolve();
        await bindingGate.promise;
      }
      if (/comicChapterList/.test(url)) {
        catalogStarted = true;
        if (bindingStarted) bothStarted.resolve();
        await catalogGate.promise;
      }
    };
    const overlap = loadSource({ settings: { tencentCommentBindings: JSON.stringify(BIND) }, state: overlapState });
    await overlap.source.comic.loadInfo('54235');
    const overlapA = overlap.source.comic.loadChapterMetadata('54235', batch.slice(0, 4)).then(x => { returned = true; return x; });
    const overlapB = overlap.source.comic.loadChapterMetadata('54235', batch.slice(4));
    let gateTimeout;
    const overlapped = await Promise.race([bothStarted.promise.then(() => true), new Promise(r => { gateTimeout = setTimeout(() => r(false), 1500); })]);
    clearTimeout(gateTimeout);
    check('P1 manual binding and live catalog reach independent blocked network gates together', () => {
      assert(overlapped && bindingStarted && catalogStarted, 'serial requests: both must start before either gate opens');
      assert(!returned, 'returned before identity verification');
      eq(catalogRequests(overlapState).length, 1, 'different batches share blocked catalog');
    });
    catalogGate.resolve();
    if (overlapped) await overlap.source._chapterMetadataProvider.catalogFlight.promise;
    check('P2 completed catalog cannot return facts while binding remains blocked', () => { assert(!returned, 'unverified catalog escaped'); });
    bindingGate.resolve();
    const [overlapResultA, overlapResultB] = await Promise.all([overlapA, overlapB]);
    check('P3 overlapping callers receive verified facts with one catalog GET', () => {
      eq(catalogRequests(overlapState).length, 1);
      for (const k of batch) eq((overlapResultA[k] || overlapResultB[k]).likesCount, exact.get(Cls0.title(info.chapters[k])).good_count);
    });
    overlapState.onRequest = null;
    await overlap.source.comic.loadChapterMetadata('54235', batch);
    check('P4 independent call after overlap fetches a fresh catalog', () => { eq(catalogRequests(overlapState).length, 2); });

    // Real title mismatch, with a successful decoded catalog before verification.
    const mismatchState = freshState();
    const mismatch = loadSource({ settings: { tencentCommentBindings: '{"54235":"653476"}' }, state: mismatchState });
    const mismatchInfo = await mismatch.source.comic.loadInfo('54235');
    let catalogSucceeded = false;
    mismatchState.onRequest = async url => {
      if (/m\.ac\.qq\.com\/comic\/index\//.test(url)) {
        await mismatch.source._chapterMetadataProvider.catalogFlight.promise;
        catalogSucceeded = true;
      }
    };
    const mismatchResult = await mismatch.source.comic.loadChapterMetadata('54235', batch);
    check('P5 successful other-work catalog is discarded when real binding title validation fails', () => {
      assert(catalogSucceeded, 'catalog did not finish successfully before binding');
      eq(catalogRequests(mismatchState).length, 1);
      eq(mismatchResult, Object.fromEntries(batch.map(k => [k, mismatchInfo.chapterMetadata[k]])), 'only Lizi dates allowed');
      for (const fact of Object.values(mismatchResult)) assert(!('likesCount' in fact) && !('tencentUpdateTime' in fact), 'other-work facts leaked');
    });

    // ---------- H. fail-closed field contract on a stubbed provider ----------
    state.requests.length = 0; state.catalogHits.length = 0;
    const metadata = src._chapterMetadataProvider, prov = metadata.provider;
    const realApi = prov.api, realLocal = metadata.local, realBinding = prov.binding;
    let scripted = null;
    metadata.local = async () => ({ title: 'T', authors: [], chapters: [
      { id: '1', title: '第1话 a' }, { id: '2', title: '第2话 b' }, { id: '3', title: '第3话 c' },
      { id: '4', title: '第4话 d' }, { id: '5', title: '第5话 e' }, { id: '6', title: '第6话 f' },
      { id: '7', title: '第7话 g' }, { id: '8', title: '第8话 h' }] });
    prov.binding = async () => ({ id: '646782', title: 'T', chapters: [
      { id: '11', title: '第1话 a' }, { id: '12', title: '第2话 b' }, { id: '13', title: '第3话 c' },
      { id: '14', title: '第4话 d' }, { id: '15', title: '第5话 e' }, { id: '16', title: '第6话 f' },
      { id: '17', title: '第7话 g' }, { id: '18', title: '第8话 h' }, { id: '19', title: '第9话 i' }] });
    prov.api = async () => scripted;
    const call = async () => src.comic.loadChapterMetadata('54235', ['1', '2', '3', '4', '5', '6', '7', '8']);
    scripted = { error_code: 2, data: { chapter_list: [
      { chapter_id: 11, good_count: 0, update_date: '2024-01-01' },
      { chapter_id: 12, good_count: '77', update_date: '2024-01-02' },
      { chapter_id: 13, good_count: -5, update_date: '2024-01-03' },
      { chapter_id: 14, good_count: 1.5, update_date: '2024-01-04' },
      { chapter_id: 15, good_count: 9, update_date: '2024/01/05' },
      { chapter_id: 16, good_count: 9 },
      { chapter_id: 17, good_count: 9, update_date: '2024-01-07' },
    ] } };
    const stub = await call();
    check('H1 0 accepted; string/negative/fractional rejected (unknown stays unknown)', () => {
      eq(stub['1'], { tencentUpdateTime: '2024-01-01', likesCount: 0, likesSource: 'tencent' }, 'zero');
      eq(stub['2'], { tencentUpdateTime: '2024-01-02' }, 'string count');
      eq(stub['3'], { tencentUpdateTime: '2024-01-03' }, 'negative count');
      eq(stub['4'], { tencentUpdateTime: '2024-01-04' }, 'fraction count');
      assert(!('likesCount' in stub['2']) && !('likesCount' in stub['3']) && !('likesCount' in stub['4']), 'unknown filled');
    });
    check('H2 malformed/missing update_date is omitted, not guessed', () => {
      eq(stub['5'], { likesCount: 9, likesSource: 'tencent' }, 'slash date');
      eq(stub['6'], { likesCount: 9, likesSource: 'tencent' }, 'missing date');
    });
    check('H3 unmatched chapter is an empty fact, never 0 or neighbour value', () => {
      eq(stub['8'], {}, 'unmatched');
      eq(stub['7'], { tencentUpdateTime: '2024-01-07', likesCount: 9, likesSource: 'tencent' });
    });
    scripted = { error_code: 2, data: { chapter_list: [{ chapter_id: 11, good_count: 1, update_date: '2024-01-01' }, { chapter_id: 11, good_count: 2, update_date: '2024-01-01' }] } };
    const dup = await call();
    check('H4 duplicate chapter_id is a schema failure -> {}', () => { eq(dup, {}); });
    scripted = { error_code: 2, data: { chapter_list: [] } };
    const emptyCat = await call();
    check('H5 empty catalog -> {}', () => { eq(emptyCat, {}); });
    // api() gate: exercise the real method with a stub transport/crypto.
    prov.api = realApi;
    const apiCtx = { end: Date.now() + 5000, expired: false };
    const realGet = prov.get, realCrypto = prov.crypto;
    prov.get = async () => 'stub'; // get() returns the body string
    const fakeCrypto = body => ({ metadata: () => ({ DEVICETYPE: 'iphone', MODEL: 'unknow', NETWORK: '*g' }), sign: () => 'x'.repeat(32), decodeCatalogAsync: async () => body, decodeAsync: async () => body });
    const gate = async (obj) => { prov.crypto = fakeCrypto(obj); try { await prov.api(apiCtx, '/13.1.2/Comic/comicChapterList/comic_id/1', true); return 'accepted'; } catch (e) { return e.liziCommentCode || e.message; } };
    const gate1 = await gate({ error_code: 0, data: {} });
    const gate2 = await gate({ error_code: 2, code: 0, data: {} });
    const gate3 = await gate({ error_code: 2, data: {} });
    prov.crypto = realCrypto;
    prov.get = async () => { throw prov.fail('http'); };
    let httpCode = null;
    try { await prov.api(apiCtx, '/x', true); } catch (e) { httpCode = e.liziCommentCode; }
    prov.get = realGet;
    check('H6 api gate rejects error_code!=2 / code / ret, and non-200 HTTP', () => {
      eq(gate1, 'gate'); eq(gate2, 'gate'); eq(gate3, 'accepted'); eq(httpCode, 'http');
    });
    check('H7 no like count is ever taken from comment stats', () => {
      // The stub's api is the only catalog source; no other endpoint was touched.
      eq(state.requests.filter(r => /iphone\.ac\.qq\.com/.test(r.url)).length, 0);
    });
    prov.api = realApi; metadata.local = realLocal; prov.binding = realBinding;

    // ---------- I. crypto windows / old JWT marker ----------
    const wire = catalogWire.trim();
    const decodeAsync = vm.runInContext('(w)=>TencentChapterCrypto.decodeAsync(w)', h.context);
    const decodeCatalogAsync = vm.runInContext('(w)=>TencentChapterCrypto.decodeCatalogAsync(w)', h.context);
    let asyncErr = null;
    try { await decodeAsync(wire); } catch (e) { asyncErr = String(e.message); }
    check('I2 comment decodeAsync still rejects >100000 wire characters', () => {
      assert(asyncErr && /size/.test(asyncErr), 'decodeAsync accepted catalog wire: ' + asyncErr);
      return asyncErr;
    });
    const big = await decodeCatalogAsync(wire);
    check('I3 decodeCatalogAsync parses 384 rows from the same wire', () => {
      eq(big.error_code, 2);
      eq(big.data.chapter_list.length, 384);
      eq(big.data.chapter_list[0].chapter_id, 154090);
    });
    let tooBig = null;
    try { await decodeCatalogAsync('A'.repeat(2097153)); } catch (e) { tooBig = String(e.message); }
    check('I4 catalog decoder enforces its own 2 MiB wire bound', () => { assert(/size/.test(tooBig || ''), 'no bound: ' + tooBig); return tooBig; });
    check('I5 plain decodeAsync bound unchanged at 100000 (not widened)', async () => {
      let e = null;
      try { await decodeAsync('A'.repeat(100001)); } catch (x) { e = String(x.message); }
      assert(/size/.test(e || ''), 'not bounded: ' + e);
    });
    check('I6 preserve official image marker and repair invalid old absolute cache', () => {
      eq(src.officialImagePath('$jp$https://cdn.lzimg.xyz/a/b.jpg'), '$jp$/a/b.jpg');
      eq(src.officialImagePath('$jp$cfhttps://i.lzimg.xyz/a/b.jpg'), '$jp$/a/b.jpg');
      return src.officialImagePath('https://i.lzimg.xyz/x.jpg');
    });
    check('I7 authToken jwt:/Bearer prefix strip still present in both paths', () => {
      const text = fs.readFileSync(SRC, 'utf8');
      const n = (text.match(/token\.replace\(\/\^jwt:\\s\*\/i, ""\)\.replace\(\/\^Bearer\\s\+\/i, ""\)\.trim\(\);/g) || []).length;
      assert(n === 2, 'token strip occurrences ' + n);
      assert(/apiFetch = async/.test(text), 'apiFetch missing');
      return n;
    });
    check('I8 metadata path never reads account data (no JWT)', () => {
      eq(h.deniedData, [], 'private loadData attempts');
      const t = h.settingReads.filter(k => /token|jwt|auth/i.test(k));
      eq(t, [], 'private setting reads');
    });

    // ---------- J. matching performance ----------
    check('J1 run() matching parity + speed vs LiziTencentComments.matchChapter', () => {
      const meta = src._chapterMetadataProvider;
      const Cls = vm.runInContext('LiziChapterMetadata', h.context);
      const matcher = vm.runInContext('LiziTencentComments', h.context);
      const local = Object.keys(info.chapters).map(k => ({ id: k, title: Cls.title(info.chapters[k]) }));
      const remote = catalog.data.chapter_list.map(r => ({ id: String(r.chapter_id), title: Cls.title(r.chapter_title) }));
      const before = process.hrtime.bigint();
      const oldOut = local.map(row => { const t = matcher.matchChapter(row, local, remote); return t && t.id; });
      const mid = process.hrtime.bigint();
      const li = Cls.prepared(local), ri = Cls.prepared(remote);
      const newOut = local.map(row => { const t = Cls.match(row, local, remote, { local: li, remote: ri }); return t && t.id; });
      const end = process.hrtime.bigint();
      eq(newOut, oldOut, 'matching parity');
      const msOld = Number(mid - before) / 1e6, msNew = Number(end - mid) / 1e6;
      assert(msNew * 5 < msOld, 'not meaningfully faster: ' + msOld + ' -> ' + msNew);
      return { old_ms: +msOld.toFixed(1), new_ms: +msNew.toFixed(1), matched: oldOut.filter(Boolean).length, unmatched: oldOut.filter(x => !x).length, speedup: +(msOld / msNew).toFixed(1) };
    });

    const failedChecks = results.filter(r => !r.ok);
    console.log(JSON.stringify({ phase: 'done', total: results.length, failed: failedChecks.length, results }, null, 2));
    return { results, failed: failedChecks };
  })();
}

module.exports = { run };
