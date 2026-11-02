import 'dart:async';
import 'dart:io';
import 'package:flutter_qjs/flutter_qjs.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FlutterQjs js;
  setUp(() async {
    js = FlutterQjs();
    unawaited(js.dispatch());
    js.evaluate(r'''
      globalThis.store={};globalThis.testPosts=0;globalThis.testBody=null;
      globalThis.responseToken='synthetic-session';
      class ComicSource {
        loadSetting(k){const saved=store.settings&&store.settings[k];
          if(saved!=null)return saved;
          if(this.settings&&this.settings[k]&&'default' in this.settings[k])return this.settings[k].default;
          throw Error('Setting not found: '+k);}
        loadData(k){return store[k];}
        saveData(k,v){store[k]=v;}
        deleteData(k){delete store[k];}
      }
      globalThis.Network={
        get:async()=>({status:200,body:'{"status":true}'}),
        sendRequest:async(method,url,headers,body,extra)=>{
          testPosts++;testBody=JSON.parse(body);
          if(method!=='POST'||url.indexOf('/app/api/user/login?')<0||!extra.maskDataInLog)
            throw Error('Invalid login protocol');
          return {status:200,body:JSON.stringify({code:201,data:{token:responseToken}})};
        }
      };
      globalThis.Convert={encodeUtf8:s=>s,md5:s=>s,hexEncode:s=>'synthetic-signature'};
      globalThis.setTimeout=(fn,ms)=>undefined;
      globalThis.UI={showMessage(){},showDialog(){}};
    ''');
    js.evaluate(await File('test/fixtures/lizimh_image_codec_release.js').readAsString());
    js.evaluate('globalThis.src=new Lizimh();void 0;');
  });
  tearDown(() {
    try { js.close(); } finally { js.port.close(); }
  });
  Future<dynamic> run(String body) async {
    final function=js.evaluate('(async()=>{$body})') as JSInvokable;
    try {
      final result=function([]);
      return result is Future ? await result : result;
    } finally { function.free(); }
  }
  test('native account login async contract stores session and rejects empty token', () async {
    final result=await run(r'''
      await src.account.login(' synthetic@example.invalid ',' fake-password ');
      const success=src.getOfficialToken()==='synthetic-session' &&
        testBody.email==='synthetic@example.invalid' && testBody.pwd==='fake-password' &&
        testPosts===1 && !('password' in store.officialSession_v1);
      responseToken='';let rejected=false;
      try{await src.account.login('synthetic@example.invalid','fake-password');}catch(e){rejected=true;}
      return {success,rejected};
    ''') as Map;
    expect(result['success'], isTrue);
    expect(result['rejected'], isTrue);
  });
  test('native logout and legacy-token compatibility do not resurrect credentials', () async {
    final result=await run(r'''
      store.settings={authToken:'fake-legacy',tencentCommentSort:'hot'};
      const migrated=src.getOfficialToken()==='fake-legacy';
      src.account.logout();
      const after=src.getOfficialToken();
      const preserved=store.settings.tencentCommentSort==='hot';
      return {migrated,cleared:after==='',preserved};
    ''') as Map;
    expect(result['migrated'], isTrue);
    expect(result['cleared'], isTrue);
    expect(result['preserved'], isTrue);
  });
  test('native settings hide requested rows but retain capability defaults', () async {
    final result=await run(r'''
      const visible=Object.keys(src.settings).filter(k=>['select','switch','input','callback'].includes(src.settings[k].type));
      return {visible,enabled:src.loadSetting('tencentCommentsEnabled'),binding:src.loadSetting('tencentCommentBindings')};
    ''') as Map;
    expect(result['visible'], ['commentProviderV2','tencentCommentSort','imageLine','imageSpeedTest','readingModeTest','maxPages']);
    expect(result['enabled'], 'on');
    expect(result['binding'], '{}');
  });
}
