const {loadSource,freshState,vm,detail,catalog}=require('./test.cjs');
const assert=require('node:assert/strict');
const h=loadSource(freshState());
const C=vm.runInContext('LiziTencentComments',h.context);
const M=vm.runInContext('LiziChapterMetadata',h.context);
const Q=vm.runInContext('QingmanProvider',h.context);
let count=0;
function test(name,local,remote,want) {
 const l=local.map((title,i)=>({id:'l'+i,title}));
 const r=remote.map((title,i)=>({id:'r'+i,title}));
 for(const [path,fn] of [['comments',()=>C.matchChapter(l[0],l,r)],['metadata',()=>M.match(l[0],l,r)],['indexed metadata',()=>M.match(l[0],l,r,{local:M.prepared(l),remote:M.prepared(r)})]]) {
  assert.equal(fn()?.id||null,want,name+' '+path);count++;
 }
 if(/^0\d/.test(local[0])) {assert.equal(Q.exactChapter(l[0],l,r)?.id||null,want,name+' provider');count++;}
}
test('exact screenshot',['091一夜春风'],['94-091春风'],'r0');
test('spaces',['091 一夜春风'],['94-091 春风'],'r0');
test('same padded subtitle',['091一夜春风'],['091一夜春风'],'r0');
test('padded explicit',['091一夜春风'],['第91话 一夜春风'],'r0');
test('different number',['091一夜春风'],['94-092春风'],null);
test('different subtitle',['091一夜春风'],['94-091秋雨'],null);
test('non-suffix',['091一夜春风'],['94-091春风一夜'],null);
test('one-character accidental suffix',['091一夜春风'],['94-091风'],null);
test('duplicate local',['091一夜春风','091另外一章'],['94-091春风'],null);
test('duplicate remote',['091一夜春风'],['94-091春风','95-091春风'],null);
test('part mismatch',['091一夜春风'],['94-091下篇春风'],null);
test('volume mismatch',['091一夜春风'],['第2卷94-091春风'],null);
test('range rejected',['091-092一夜春风'],['94-091春风'],null);
test('ordinary bare number not widened',['91一夜春风'],['94-091春风'],null);
test('ordinary suffix not widened',['第91话一夜春风'],['第91话春风'],null);
test('ordinary same title unchanged',['第91话一夜春风'],['第91话一夜春风'],'r0');
const raw=detail.data.chapters.filter(x=>/091|春风/.test(x.name));
const qq=catalog.data.chapter_list.filter(x=>/091|春风/.test(x.chapter_title));
console.log(JSON.stringify({passed:count,realFixtureLocal:raw,realFixtureTencent:qq},null,2));
