'use strict';
/* Offline contract + performance verification for the generated 2.33.24 source.
 * Read-only: no publish, no commit, no writes outside this directory.
 * Every network call is answered by a fixture; live.cjs performs real HTTPS GET. */
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const { parseHTML } = require('linkedom');

const ROOT = __dirname;
const INIT = path.resolve(ROOT, '../../assets/init.js');
const SRC = path.join(ROOT, '../fixtures/lizimh_image_codec_release.js');
const RES = path.join(ROOT, 'research');

const detail = JSON.parse(fs.readFileSync(path.join(ROOT, 'fixtures/detail-54235.json'), 'utf8'));
const catalogWire = fs.readFileSync(path.join(RES, 'catalog-comicChapterList.wire'), 'utf8');
const catalog = JSON.parse(fs.readFileSync(path.join(RES, 'catalog-comicChapterList.json'), 'utf8'));
const catalog2Wire = fs.readFileSync(path.join(RES, 'catalog-653476.wire'), 'utf8');
const catalog2 = JSON.parse(fs.readFileSync(path.join(RES, 'catalog-653476.json'), 'utf8'));

function ab(b) { return b.buffer.slice(b.byteOffset, b.byteOffset + b.byteLength); }
function buf(b) { return ArrayBuffer.isView(b) ? Buffer.from(b.buffer, b.byteOffset, b.byteLength) : Buffer.from(b); }

function html(body) { return '<!doctype html><html><body>' + body + '</body></html>'; }
function comicPage(title, firstCid) {
  return html('<div class="head-title-tags"><h1>' + title + '</h1></div>' +
    '<a class="chapter-link" data-cid="' + firstCid + '" href="#">x</a>');
}
function chapterPage(rows) {
  const raw = rows.map(r => ({ cid: r.chapter_id, title: r.chapter_title }));
  return html('<div id="data_chapterInfo">' + JSON.stringify(raw) + '</div>');
}

/* Mutable fixture router: tests flip `mode` and `delay`. */
function makeFixture(state) {
  return async function fixture(url, headers) {
    state.requests.push({ url, headers: Object.assign({}, headers), at: Date.now() });
    if (state.onRequest) await state.onRequest(url);
    const u = new URL(url);
    const p = u.pathname;
    if (u.hostname === 'ai.xajtl.com' || u.hostname === 'ai.qsmm.fun') {
      if (/^\/app\/api\/v2\/detail\/54235$/.test(p)) return { status: 200, body: JSON.stringify(detail) };
      if (/^\/app\/api\/v2\/detail\/999$/.test(p)) return { status: 200, body: JSON.stringify(state.detail999) };
      throw new Error('FIXTURE_UNKNOWN_LIZI ' + p);
    }
    if (u.hostname === 'm.ac.qq.com') {
      if (/^\/comic\/index\/id\/646782$/.test(p)) return { status: 200, body: comicPage('全球高武', 2) };
      if (/^\/comic\/index\/id\/653476$/.test(p)) return { status: 200, body: comicPage('小飞侠', 2387) };
      if (/^\/chapter\/index\/id\/646782\/cid\/2$/.test(p)) return { status: 200, body: chapterPage(catalog.data.chapter_list) };
      if (/^\/chapter\/index\/id\/653476\/cid\/2387$/.test(p)) return { status: 200, body: chapterPage(catalog2.data.chapter_list) };
      throw new Error('FIXTURE_UNKNOWN_TENCENT ' + p);
    }
    if (u.hostname === 'iphone.ac.qq.com') {
      const m = p.match(/^\/13\.1\.2\/Comic\/comicChapterList\/comic_id\/(\d+)$/);
      if (!m) throw new Error('FIXTURE_UNKNOWN_API ' + p);
      state.catalogHits.push({ id: m[1], at: Date.now() });
      if (state.delay) await new Promise(r => setTimeout(r, state.delay));
      if (state.catalogMode === 'fail500') return { status: 500, body: '' };
      if (state.catalogMode === 'zero') return { status: 200, body: '' };
      return { status: 200, body: m[1] === '653476' ? catalog2Wire : catalogWire };
    }
    throw new Error('FIXTURE_HOST ' + u.hostname);
  };
}

class Element {
  constructor(e) { this.e = e; }
  querySelector(q) { const e = this.e.querySelector(q); return e ? new Element(e) : null; }
  querySelectorAll(q) { return Array.from(this.e.querySelectorAll(q), e => new Element(e)); }
  get text() { return this.e.textContent; }
  get attributes() { return Object.fromEntries(Array.from(this.e.attributes || [], x => [x.name, x.value])); }
  get children() { return Array.from(this.e.children || [], e => new Element(e)); }
  get innerHTML() { return this.e.innerHTML; }
  get parent() { return this.e.parentElement ? new Element(this.e.parentElement) : null; }
  get classNames() { return Array.from(this.e.classList || []); }
  get id() { return this.e.id || null; }
  get localName() { return this.e.localName; }
  get previousElementSibling() { return this.e.previousElementSibling ? new Element(this.e.previousElementSibling) : null; }
  get nextElementSibling() { return this.e.nextElementSibling ? new Element(this.e.nextElementSibling) : null; }
}
class HtmlDocument extends Element {
  constructor(h) { super(parseHTML(h).document); }
  getElementById(id) { const e = this.e.getElementById(id); return e ? new Element(e) : null; }
  dispose() { this.e = null; }
}

function loadSource({ file = SRC, settings = {}, data = {}, state, initFile = INIT } = {}) {
  const fixture = makeFixture(state);
  const deniedData = [], settingReads = [];
  class ComicSource {
    loadSetting(k) { settingReads.push(k); return Object.prototype.hasOwnProperty.call(settings, k) ? settings[k] : undefined; }
    loadData(k) { if (/auth|token|cookie|device|jwt|sign/i.test(k)) { deniedData.push(k); throw new Error('QA_PRIVATE_DATA_FORBIDDEN'); } return data[k]; }
    saveData() { throw new Error('QA_PERSISTENCE_FORBIDDEN'); }
    deleteData() { throw new Error('QA_PERSISTENCE_FORBIDDEN'); }
  }
  const Convert = {
    encodeUtf8: s => ab(Buffer.from(s, 'utf8')), decodeUtf8: b => buf(b).toString('utf8'),
    decodeBase64: s => ab(Buffer.from(s, 'base64')), encodeBase64: b => buf(b).toString('base64'),
    hexEncode: b => buf(b).toString('hex'), hexDecode: s => ab(Buffer.from(s, 'hex')),
    md5: b => ab(crypto.createHash('md5').update(buf(b)).digest()),
    sha1: b => ab(crypto.createHash('sha1').update(buf(b)).digest()),
  };
  const context = vm.createContext({
    ComicSource, Convert, HtmlDocument, ArrayBuffer, Uint8Array, TextEncoder, TextDecoder, URL,
    setTimeout, clearTimeout, setInterval, clearInterval,
    console: { log() {}, warn() {}, error() {} },
    Network: { async get(url, headers) { return fixture(url, headers); }, async sendRequest(method, url, headers) { if (method !== 'GET') throw new Error('GET_ONLY'); return fixture(url, headers); } },
  });
  const init = fs.readFileSync(initFile, 'utf8');
  for (const name of ['Comic', 'ComicDetails', 'Comment']) {
    const start = init.indexOf(`function ${name}(`), end = init.indexOf('\n}', start) + 2;
    vm.runInContext(init.slice(start, end), context, { filename: initFile });
  }
  const text = fs.readFileSync(file, 'utf8');
  vm.runInContext(text + '\n;globalThis.__qaSource = new Lizimh();', context, { timeout: 5000, filename: file });
  return { source: context.__qaSource, context, state, deniedData, settingReads,
    sha256: crypto.createHash('sha256').update(text).digest('hex'), version: context.__qaSource.version };
}

const results = [];
function check(name, fn) {
  try { const detail2 = fn(); results.push({ name, ok: true, detail: detail2 === undefined ? null : detail2 }); }
  catch (e) { results.push({ name, ok: false, error: String(e && e.message || e) }); }
}
function assert(cond, msg) { if (!cond) throw new Error(msg || 'assertion failed'); }
function eq(a, b, msg) { const A = JSON.stringify(a), B = JSON.stringify(b); if (A !== B) throw new Error((msg || 'not equal') + ' got=' + A + ' want=' + B); }

function freshState(over) {
  return Object.assign({ requests: [], catalogHits: [], catalogMode: 'ok', delay: 0, detail999: null }, over || {});
}
function catalogRequests(state) { return state.requests.filter(r => /comicChapterList/.test(r.url)); }
function clean(body) { try { return JSON.parse(body); } catch (_) { return null; } }
function decodeWire(ctx, wire, method) {
  return vm.runInContext('__qaSource && (function(){return TencentChapterCrypto.' + method + '})()' , ctx);
}

module.exports = { loadSource, check, results, assert, eq, freshState, catalogRequests, SRC, INIT, RES, detail, catalog, catalog2, catalogWire, catalog2Wire, vm, fs, path, parseHTML };

if (require.main === module) {
  Promise.resolve(require('./tests.cjs').run({ loadSource, check, results, assert, eq, freshState, catalogRequests,
    detail, catalog, catalog2, catalogWire, catalog2Wire, vm, fs, path, SRC, RES, SRC_DIR: ROOT }))
    .then(() => {
      const failed = results.filter(r => !r.ok);
      console.log(JSON.stringify({ summary: { total: results.length, failed: failed.length, sha256: crypto.createHash('sha256').update(fs.readFileSync(SRC)).digest('hex') }, failures: failed }, null, 2));
      process.exit(failed.length ? 1 : 0);
    })
    .catch(e => { console.error('FATAL', e); process.exit(2); });
}
