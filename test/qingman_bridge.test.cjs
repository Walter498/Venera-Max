const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const root = path.resolve(__dirname, '..');
const init = fs.readFileSync(path.join(root, 'assets/init.js'), 'utf8');
const start = init.indexOf('const Qingman = Object.freeze(');
const end = init.indexOf('\n\nlet Network =', start);
function bridge(sendMessage) {
  const context = vm.createContext({sendMessage});
  vm.runInContext(init.slice(start, end) + '\nthis.bridge = Qingman;', context);
  return context.bridge;
}
test('Qingman request sends only path/params and returns parsed business JSON', async () => {
  let message;
  const q = bridge(async m => {message = m; return {status:200, body:'{"code":1,"data":{"datas":[],"total":0}}'};});
  const r = await q.request('/api/comic/comments/fu893u94/chapterList', {chapterId:'42',page:1,size:20,sort:0});
  assert.equal(r.code, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(message)), {method:'qingman',path:'/api/comic/comments/fu893u94/chapterList',params:{chapterId:'42',page:1,size:20,sort:0}});
  assert.equal(r.status, undefined);
});
test('native fixed error and malformed JSON do not leak parser input', async () => {
  await assert.rejects(bridge(async () => ({error:'青漫尚未导入配置'})).request('/x'), /青漫尚未导入配置/);
  await assert.rejects(bridge(async () => ({body:'SECRET-SENTINEL'})).request('/x'), e =>
    e.message === '青漫响应格式无效' && !String(e).includes('SECRET-SENTINEL'));
});
test('bridge retains native-normalized 19 digit IDs as exact strings', async () => {
  const q = bridge(async () => ({status:200,
    body:'{"code":1,"data":{"id":"1965626277746577408"}}'}));
  assert.equal((await q.request('/x')).data.id, '1965626277746577408');
});
test('profileStatus is native status-only; import is not exposed to JS', async () => {
  let message;
  const q = bridge(async m => {message=m; return {installed:false,code:'missingProfile'};});
  assert.equal((await q.profileStatus()).installed, false);
  assert.deepEqual(JSON.parse(JSON.stringify(message)), {method:'qingman',action:'profileStatus'});
  assert.equal(q.importProfile, undefined);
  assert.equal(Object.isFrozen(q), true);
});
test('static security gates retain TLS hostname, no redirects or log coupling', () => {
  const native = fs.readFileSync(path.join(root,'lib/network/qingman_transport.dart'),'utf8');
  const profile = fs.readFileSync(path.join(root,'lib/network/qingman_profile.dart'),'utf8');
  const engine = fs.readFileSync(path.join(root,'lib/foundation/js_engine.dart'),'utf8');
  assert.match(profile, /SecurityContext\(withTrustedRoots: true\)/);
  assert.match(profile, /setTrustedCertificatesBytes/);
  assert.match(profile, /useCertificateChainBytes/);
  assert.match(profile, /usePrivateKeyBytes/);
  assert.doesNotMatch(native, /badCertificateCallback\s*=/);
  assert.match(native, /request\.followRedirects = false/);
  assert.match(native, /result\.status == 401/);
  assert.doesNotMatch(native + profile, /Log\.|print\(|debugPrint\(/);
  assert.ok(engine.indexOf('return handleQingmanMessage(message)') < engine.indexOf('    try {', engine.indexOf('Object? _messageReceiver')));
  assert.match(native, /out\[idKey\]/);
  assert.match(native, /\['page', 'size', sortKey\]/);
});
