'use strict';
const assert=require('assert/strict'),fs=require('fs');
const {loadSource,freshState,vm}=require('./test.cjs');
const h=loadSource(freshState()),C=vm.runInContext('LiziTencentComments',h.context),M=vm.runInContext('LiziChapterMetadata',h.context);
let count=0;
function check(name,lt,rt,want,index=1){
 const l=lt.map((title,i)=>({id:'l'+i,title})),r=rt.map((title,i)=>({id:'r'+i,title})),row=l[index];
 const idx={local:M.prepared(l),remote:M.prepared(r)};
 for(const run of [()=>C.matchChapter(row,l,r),()=>M.match(row,l,r),()=>M.match(row,l,r,idx)]){assert.equal(run()?.id||null,want,name);count++;}
}
const L=['090带薪休假','091一夜春风','092八品修身'],R=['090带薪休假','091春风','092八品修身'];
check('real web title without ordinal',L,R,'r1');
check('explicit chapter suffix shortening',['第90话带薪休假','第91话一夜春风','第92话八品修身'],['第90话带薪休假','第91话春风','第92话八品修身'],'r1');
check('prefix shortening',['022作词','023不能破身','024绝世之诗'],['022作词','023不能破','024绝世之诗'],'r1');
check('single character title with two anchors',['069打茶围','070过夜','071长夜漫漫','072元素周期表'],['069打茶围','070夜','071漫漫','072元素周期表'],'r1');
check('one typo with two anchors',['090带薪休假','091一夜春疯','092八品修身'],['090带薪休假','091一夜春风','092八品修身'],'r1');
check('different subtitle despite anchors',L,['090带薪休假','091秋雨','092八品修身'],null);
check('different number despite anchors',L,['090带薪休假','093春风','092八品修身'],null);
check('no anchors',['091一夜春风'],['091春风'],null,0);
check('only previous anchor',L.slice(0,2),R.slice(0,2),null);
check('only next anchor',L.slice(1),R.slice(1),null,0);
check('reversed remote ordering',L,['092八品修身','091春风','090带薪休假'],null);
check('no opposite volume anchors',L,['第2卷090带薪休假','091春风','第2卷092八品修身'],null);
check('part mismatch',L,['090带薪休假','091下篇春风','092八品修身'],null);
check('duplicate remote identity',L,[...R,'第91话另一章'],null);
check('duplicate local identity',[...L,'第91话另一章'],R,null);
check('range title',['090带薪休假','091-092一夜春风','092八品修身'],R,null);
check('cosmetic punctuation',['091一夜春风！'],['第91话一夜春风'], 'r0',0);
check('cosmetic traditional spacing',['091一夜春風 ！'],['第 91 话 一夜春风'], 'r0',0);
check('missing unit after 第',['第424担任主办官'],['424担任主办官'],'r0',0);
check('duplicate 第 not ignored',['第425白嫖魔法书','425白嫖魔法书'],['425白嫖魔法书'],null,0);
const local=JSON.parse(fs.readFileSync(__dirname+'/fixtures/dafeng-live/local.json')).chapters;
const remote=JSON.parse(fs.readFileSync(__dirname+'/fixtures/dafeng-live/remote-650207.json')).chapters;
const idx={local:M.prepared(local),remote:M.prepared(remote)};
for(const [id,want] of [['21','1004'],['25','1008'],['73','1602'],['74','1636'],['94','1828'],['433','60710']]){
 const row=local.find(x=>x.id===id);assert.equal(C.matchChapter(row,local,remote)?.id,want);assert.equal(M.match(row,local,remote,idx)?.id,want);count+=2;
}
const missing=[],matched=[];
for(const row of local){const target=M.match(row,local,remote,idx);if(target)matched.push({local:row.id,remote:target.id});else missing.push(row);}
assert(!missing.some(x=>['21','25','73','74','94','433'].includes(x.id)));count++;
console.log(JSON.stringify({passed:count,realCatalog:{local:local.length,remote:remote.length,matched:matched.length,missing}},null,2));
