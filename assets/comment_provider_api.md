# 评论提供方元数据

可选的 `comic.commentProviderSetting` 是源 settings 中一个 `type: 'select'` 项的键，不是全局 provider 注册表。

```js
comic = {
  commentProviderSetting: 'commentProvider',
  // 其余原有评论钩子不变；按当前 provider 返回动态 capabilities。
};
settings = {
  commentProvider: {
    title: '默认评论接口', type: 'select', default: 'tencent',
    options: [{value: 'tencent', text: '腾讯'}, {value: 'qingman', text: '青漫'}]
  }
};
```

这正是现有源设置页支持的 schema：options 是 `{value,text}` 对象数组，default 是 value；不是 map，也不是 `selectOptions`。

App 从 `getSettingsDynamic() ?? settings` 读取候选与默认值。未声明元数据或没有合法 select 候选时不显示选择器，也不扩展其他源的能力。

章末标题区、详情区和完整评论页选择器写入同一个 `source.data.settings[settingKey]`，调用原源设置页相同的 `saveData()`。该方法同步发出 `ComicSource.settingsChanges`，使所有消费者按 `commentScopeRevision` 更换 generation。持久化仍沿用原源数据文件和同步策略，不另建 provider 偏好文件。

切换后必须重新读取动态 `commentCapabilities` / `chapterCommentCapabilities`；排序仅列举当前 provider 的 sorts，默认值随新 controller 重置。青漫匿名回复返回401，因此源应声明 `canLoadReplies: false`；本集成的声明式只读 provider 同时隐藏源遗留发送/点赞/投票入口，不能复用腾讯动作。旧 provider 回复页不得将父评论 ID 交给新 provider。

显式不可用/空响应仍保留声明提供方的恢复选择器；没有提供方元数据的旧源延续原有隐藏行为。章末仍为最多四条、自然高度、无内部滚动，未制造 total/available/reply 等缺失元数据。

菜单中的“青漫连接配置”进入 native owner 的真实 `QingmanProfilePage`。只导入用户有权使用的私有 `.qmprofile`，保存在 App 私有目录；不在源脚本、公有附件或日志中放密钥，不要求密钥开关。未配置青漫仍可切回默认腾讯。此入口不代表自动作品/章节匹配已获验证；不能把作品评论冒充章评论，目录映射未证时使用源的显式手动匹配或不可用状态。
