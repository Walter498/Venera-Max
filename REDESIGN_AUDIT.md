# VeneraX 3.0 定制版 UI / 交互重构审计（对齐 iOS 26 HIG + Liquid Glass，适配 iOS 17–27）

范围与方法：只读源码，未改任何代码、未跑测试、未做真机截图。行号来自对当前工作区的 `rg` 扫描。下文"未核实"的条目是我没读到对应代码、需要你确认的地方。Apple 文本样式用 iOS 默认档：Large Title 34 / Title1 28 / Title2 22 / Title3 20 / Headline 17 semibold / Body 17 / Callout 16 / Subheadline 15 / Footnote 13 / Caption1 12 / Caption2 11（最小 11）。

---

## 0. 摘要

### 0.1 全局量化结论（`lib/` 全量统计）

| 维度 | 现状 | 含义 |
|---|---|---|
| 圆角 | 21 种取值；8px×94、12×49、16×28、4×23、10×18、14×17、6×16、20×14 | 令牌只定义了 10/16 两档，但最常用的是 8 和 12 |
| 字号 | `fontSize:` 12×82、11×52、13×43、14×29、10×23、16×14；`ts.s12`×104、`ts.s14`×81、`ts.s16`×39 | 正文实际是 12–14pt，低于 iOS 正文 17pt；10pt 及以下 29 处低于 11pt 下限 |
| 令牌覆盖 | `VeneraDesignTokens.of` 只有 18 处 / 8 个文件 | 130 个页面里绝大多数没接入令牌 |
| 动画时长 | 200ms×38、100×16、500×11、180×9、250/300/50/20 各 5、220×4、160/140 各 3 | 无统一时长与曲线 |
| 硬编码颜色 | `Colors.black/white/grey/red/green/blue/orange` 93 处 / 27 文件 | 深色模式与增强对比度下不可控 |
| Material 控件 | `IconButton` 220 处 / 82 文件、`showDialog` 98 / 48、`RadioListTile` 39 / 10、`CheckboxListTile` 24 / 17、`PopupMenu*` 31 / 11、Material `Chip` 系 33 / 13、`Cupertino` 仅 1 处 | 整体是 Material 3 骨架上叠了一层"iOS 味"令牌 |
| 触感与无障碍 | `HapticFeedback` 6 处 / 2 文件；`disableAnimations/highContrast` 等 2 处 / 2 文件；`Semantics(` 30 处 | 没有减弱动态效果、降低透明度、增强对比度的降级路径 |

### 0.2 最关键的 18 条问题

1. **主题层没有任何组件主题**（`lib/main.dart` `getTheme()`）：只设了 `colorScheme / scaffoldBackgroundColor / dividerTheme / sliderTheme / expansionTileTheme`，没有 `textTheme / appBarTheme / 各按钮主题 / listTileTheme / dialogTheme / bottomSheetTheme / switchTheme / chipTheme / splashFactory`。220 个 `IconButton`、98 个对话框都在用 M3 默认外观。这是杠杆最大的一处。
2. **配色用 `FlexTones.vividBackground`**（`main.dart`）：背景和表面被主色染色，是 Material You 观感；iOS 需要中性的 system / grouped 三级背景。
3. **令牌与实际用量脱节**：`controlRadius 16 / cardRadius 10 / sectionRadius 16`，而代码里 8px 用了 94 次、12px 用了 49 次。
4. **玻璃用在内容层**（`components/search_field.dart:133-150`、`home_page.dart:612`）：首页搜索框和同步按钮在 iOS 上用 `glassSurface + BackdropFilter`，它们是随内容滚动的内容层元素，HIG 明确不建议。而真正的导航层顶栏（`navigation_bar.dart` `buildTop`）只有半透明色、没有模糊，且处在 `Column` 里不压在内容上方，玻璃没有东西可透。
5. **顶栏 48pt 塞 4 个图标**（`main_page.dart` `paneActions` + `navigation_bar.dart` `buildTop`）：搜索/抽卡/任务/设置四个 `IconButton` 加 `titleLarge w600` 标题，无大标题、无滚动折叠。
6. **`Appbar` 是 Android 形态**（`components/appbar.dart:255-300`）：`Icons.arrow_back`、标题 20pt 左对齐、滚动后 `elevation 2`（shadow 样式）。全 App 二级页共用。
7. **自绘 `Button` 最小高度 32、无按压态**（`components/button.dart:206`）：`minHeight 32`、`GestureDetector` 只有 hover 反馈；`_IconButton` 实际点击区 36×36。
8. **`AppTabBar` 选中态只靠颜色**（`appbar.dart:694-712`）：选中与未选中同为 `w500`，只变 `primary` 色；单个 tab 可点高度 36（48 − 上下各 6）。
9. **书架二级工具条触控目标过小**（`favorites/shelf_page.dart:404-450`）：44pt 高的行里，"編輯/完成"是 13pt 纯文字 `InkWell`（无 padding），排序是 22pt 图标加左右 8 padding，文件夹选择是 16pt 文字加下拉箭头。
10. **书架顶部是默认 Material `TabBar` + 自绘胶囊**（`shelf_page.dart:66-108`）：下划线 Tab 与"緩存中心"胶囊（约 28pt 高、12pt 字）并排，标签是写死的繁体字符串。
11. **详情页顶栏最多 6 个图标**（`comic_details_page/comic_page.dart:805-848`）：清理/下载/分享/刷新/更多等并排，另有 Material `FloatingActionButton` 回顶（`:423`）。
12. **详情页标签用 10 色彩虹**（`comic_page.dart:1380-1393`）：标签组标题轮流用 `Colors.blue/cyan/red/pink/purple/indigo/teal/green/lime/yellow`。
13. **阅读器栏用硬编码灰线和两套透明度**（`reader/scaffold.dart:378-392, 1088-1100`）：`Colors.grey.toOpacity(0.5)` 分隔线；`ui_style == 'glass'` 时 0.55，否则 0.92。`ui_style` 全 App 只在 3 处生效（底栏非 iOS 分支、阅读器顶/底栏）。
14. **阅读器上一章/下一章是 13pt 文字**（`scaffold.dart:1034-1057`）：`GestureDetector` 加左右 6 padding，远小于 44pt。
15. **社区页控件尺寸普遍过小**（`community/community_page.dart`、`post_detail_page.dart`）：帖内漫画标题 10pt、点赞图标 16pt / 回复图标 12pt 的裸 `InkWell`、`more_vert` 18pt、正文用 `colorScheme.outline` 当文字色。
16. **设置页字号整体偏小且自成一套**（`settings/settings_layout.dart`、`settings_page.dart`）：行标题 14、副标题 12、组标题 13、图标 21、chevron 18、组圆角 12、行内 `ListTile` 圆角 9、页标题 27。结构已接近 iOS 分组列表，只差参数。
17. **搜索结果页两个相同的筛选图标**（`search_result_page.dart:609, 617`）：两个 `Icons.filter_alt_outlined` 按钮并排，用户无法区分。
18. **封面卡片阴影与角标配色不一致**（`components/comic.dart:739-747, 860-868, 507-540`）：详细模式用 `outlineVariant` 1px 阴影，简略模式用 `black 0.2 / blur 2 / y2`；收藏、历史角标是 `Colors.green / orange / blue` 的 24×24 方块。

### 0.3 执行波次（详见 B 节）

- **波次 0**：补令牌 + 主题层组件主题（不动页面）。
- **波次 1**：共享基础控件（`Button`、`Appbar`、`AppTabBar`、`AppSearchField`、`Select`、`ContentDialog`、toast、菜单）。
- **波次 2**：导航框架（顶栏、非 iOS 底栏、侧栏）与封面卡片（`ComicTile` / `SimpleComicTile`）。
- **波次 3**：首页、书架/收藏、详情页。
- **波次 4**：阅读器外壳。
- **波次 5**：分类/搜索、设置。
- **波次 6**：社区、评论、其余叶子页与对话框清理。

### 0.4 高风险区（详见 C 节）

- `AppSearchField.toolbarHeight` 被测试断言为精确值；`MenuButton` 被断言为 48×48。
- 设置页：行 `InkWell` 宽度必须等于分组 `Material(shape: RoundedRectangleBorder)` 宽度（±0.5），且 `Switch` / `TextField` / `settings-category-N` 键被 CI 测试直接查找。
- 评论相关 3 个 golden 测试（8 张基准图）：任何像素变化都会失败。
- 底部导航：标签文字必须保留且每个只出现一次；测试按 `Icons.bookmark_outlined` 点击。
- 阅读器手势与按钮：点击分区 30% / 40% / 30%、双击 200ms、长按 250ms，以及夜间模式、自动翻页按钮被按 `IconButton` 类型查找。
- 收藏页：一组 tooltip 文案、`CloseButton`、`TextButton` 面包屑、`ListTile` 被测试查找。
- iOS 底栏是原生 `UITabBar` 平台视图，Flutter 侧只管高度和标签。

---

## 1. 逐界面问题清单

### 1.1 主导航框架

**`lib/main.dart` — `getTheme()`**
- 现状：`useMaterial3: true`；`SeedColorScheme.fromSeeds(... tones: FlexTones.vividBackground)`；主色来自 `Colors.red/pink/purple/green/orange/blue/yellow/cyan`；`dividerTheme` 0.5 厚、`outlineVariant` 26% 透明；无 `textTheme` 与任何组件主题。
- 问题：表面带主色染色；Material 主色不是 iOS 系统色；所有未单独定制的控件是 M3 默认形态（胶囊按钮、水波纹、28dp 圆角对话框）。
- 建议：
  - 背景改中性三级：浅色 `#FFFFFF / #F2F2F7 / #FFFFFF`（system / grouped / grouped 二级），深色 `#000000 / #1C1C1E / #2C2C2E`；主色只作 accent。
  - 主色表换成 iOS 系统色的浅/深两套值（如 blue `#007AFF / #0A84FF`）。
  - 加 `textTheme`（映射见 A 节）、`appBarTheme`、`filledButtonTheme / textButtonTheme / outlinedButtonTheme`（最小高度 44，圆角 12，文字 17 semibold）、`iconButtonTheme`（最小 44×44）、`listTileTheme`（最小高度 44，标题 17）、`dialogTheme`（圆角 14）、`bottomSheetTheme`（顶部圆角 16 加拖动条）、`switchTheme`、`chipTheme`。
  - iOS 上 `splashFactory: NoSplash.splashFactory`，改用高亮色做按压反馈。

**`lib/pages/main_page.dart`**
- 现状：4 个标签（首页/收藏/社區/分类），Material 图标 `home / local_activity / forum / category`；`'社區'` 是硬编码字符串，其余走 `.tl`；`paneActions` 最多 4 项（搜索在首页隐藏）。
- 问题：标签数量合适，但顶栏动作过多（HIG：标签栏用于导航，动作放工具栏且要克制）；"收藏"用 `local_activity`（票券）图标语义不符；一处文案未本地化。
- 建议：顶栏只留 1–2 个动作（搜索 + 一个"更多"下拉菜单收纳抽卡/任务/设置），或把设置放到首页大标题右侧的头像位；`'社區'` 改走翻译表。iOS 实际图标在 `ios/Runner/AppDelegate.swift:283-284` 用 SF Symbols 定义，Flutter 侧图标只影响非 iOS。

**`lib/components/navigation_bar.dart`**
- 现状：
  - 常量：底栏 64、顶栏 48、折叠侧栏 72、展开侧栏 224。
  - `buildTop`（约 `:262-300`）：`Material(color: glassSurface)`，底边 0.6 线，标题 `titleLarge w600`，右侧 `IconButton` 列表。
  - `buildBottom` 非 iOS 玻璃分支（`:321-375`）：顶部圆角 22、`blur 18`、`surfaceContainerHigh` 55%（用已弃用的 `withOpacity`）；普通分支 1px `outlineVariant` 顶线。
  - `_SingleBottomNaviWidget`（约 `:594-726`）：图标底板 32→64 × 28、圆角 12、`secondaryContainer`；标签 `fontSize 11, height 1.0`，选中 `primary`；整格 60 高；`GestureDetector` 无按压态。
  - `_SideNaviWidget` / `_PaneActionWidget`：高 38、圆角 12、选中 `primaryContainer`，文字无字重变化。
  - 侧栏：不透明 `Material`，右边 1.0 `outlineVariant` 线；Logo 文字 22 / w800。
  - 页面切换：`AnimatedSwitcher` 140ms。
- 问题：
  - 顶栏不是玻璃（无 `BackdropFilter`，且不覆盖内容），与令牌名 `glassSurface` 不符。
  - 底栏选中态有"底板 + 实心图标 + 颜色"三重表达，这点是好的；但 M3 药丸底板是 Android 观感。
  - 侧栏行高 38 < 44；选中只靠底色，图标换实心但文字不加粗。
  - 侧栏按 iPadOS 26 应是浮在内容上的玻璃层，现在是带分隔线的不透明面板。
  - 标签 `height: 1.0` 且外框固定 60，大字号下会裁切。
- 建议：
  - 顶栏改为覆盖内容的大标题导航：展开 96（Large Title 34 bold）、折叠 44（Headline 17 semibold 居中），折叠后背景才出现材质与 0.5 发丝线（滚动边缘效果）。
  - 非 iOS 底栏：去掉顶部 22 圆角的"半圆条"，改全宽材质条；高度用 49 + 安全区；标签 Caption2 11 / medium，选中 semibold + accent + 实心图标，去掉药丸底板。
  - 侧栏行高 44、圆角 10、水平 padding 12、图标 22、文字 Body 17（选中 semibold）；背景用较厚材质（约 86% 不透明 + blur 30），去掉 1px 右边线改用阴影分离。
  - 标签去掉固定 `height: 1.0`，外框用 `minHeight` 而非固定高度。

**`lib/components/native_tab_bar.dart`**
- 现状：iOS 用 `UiKitView('venera/native_tab_bar')`，高度 `64 + bottomInset`；`AppDelegate.swift:226-243` 设置 `isTranslucent = true`、`configureWithDefaultBackground()`。
- 问题：系统 `UITabBar` 标准高度是 49，Flutter 侧预留 64；iOS 26 的浮动标签栏尺寸与位置又不同，写死 64 在 17–27 各版本上会出现多余空白或遮挡。各页面底部是否按这个高度留白未核实。
- 建议：让原生侧通过 MethodChannel 回报实际占用高度（含 iOS 26 浮动栏的外边距），Flutter 侧存进一个 `InheritedWidget`，所有可滚动页用它做底部 `contentInset`。这是 Liquid Glass 最正统的落点，保留原生实现，不要用 Flutter 重画。

**`lib/components/side_bar.dart`**（`SideBarRoute`）
- 现状：左侧圆角 16、底色 `colorScheme.surfaceTint`（约 `:102`）、阴影 `Colors.white.withAlpha(50)` blur 10、遮罩 `Colors.black54`、220ms `easeOutCubic`、默认宽 500。
- 问题：白色发光阴影在浅色模式几乎不可见、深色模式是光晕，属于装饰性阴影；`surfaceTint` 当底色是主色染色；54% 黑遮罩偏重。
- 建议：改成 sheet 语义。手机上用底部 sheet（medium / large 两档、顶部圆角 16、拖动条）；宽屏保留右侧面板但用厚材质 + `black 20%` 遮罩，去掉白色阴影。

### 1.2 首页

**`lib/pages/home_page.dart`**
- 现状：
  - 分区容器 `_HomeSectionSurface`（`:88-110`）：外边距水平 12 / 垂直 6，`contentSurface`，圆角 16，0.7 边框。
  - 分区头：高 56，图标 20，标题 `titleMedium w600`，chevron 占位 32×56；内部 `InkWell` 圆角 8（`:714-716, 849, 973, 1061, 1716, 1904`）。
  - 计数徽标 `_HomeCountBadge`：高 22、圆角 11、`secondaryContainer`、`labelSmall`。
  - 搜索行 `_SearchBar`（`:479-520`）：外边距水平 8，三个 52×52 的方块并排（搜索框 + 同步 + 编辑），间距 8。
  - 编辑横幅与编辑条（`:373-455`）：外边距水平 8、圆角 8、0.6 边框。
  - 封面 98×136（宽屏 106 / 112）。
  - 图片收藏 Tab（`:1988-2060`）：高 44、3px 下划线指示器、`s16 w500`。
  - 导入对话框（`:1286-1335`）：`RadioListTile / CheckboxListTile`，固定 `SizedBox(width: 600)`。
- 问题：
  - 水平边距 8 与 12 混用，搜索行和分区卡片左右不对齐。
  - 容器圆角 16、内部水波纹圆角 8，按下时高亮形状与卡片不贴合。
  - 每个分区都是"带边框的圆角卡 + 标题行 + 横向封面"，整页同一模板重复 6–8 次，是典型的模板感来源。
  - 搜索行三个等权重方块抢视觉；同步与编辑不是高频主操作。
  - 下划线 Tab 是 Material 形态。
- 建议：
  - 统一页面水平边距 16（宽屏 20），所有块对齐。
  - 分区去掉边框卡片，改"分区标题（Title3 20 semibold，右侧'查看全部' + chevron，整行 44 高）+ 无底板横向封面"，分区间距 24；只有"阅读统计""源更新"这类设置型入口保留分组列表样式（圆角 12、行高 44）。
  - 搜索框高 44、圆角 12、图标 18、提示文字 Body 17，底色用三级填充色而非玻璃；同步和编辑收进导航栏右侧。
  - 图片收藏 Tab 换成 `VeneraSegmentedControl`。
  - 计数徽标改纯文字次级色（Subheadline 15），不要底板。

**`lib/pages/home_source_feed.dart`**
- 现状：源切换 chips 行高 52，chip 实际高 36、圆角 20、水平 padding 14、0.6 边框、`GestureDetector`（`:299-340`）；星期 chips 行高 46，chip 高 34、水平 padding 16（`:399-435`）；分区标题是"4×18 主色竖条 + `s18 w600`"（`:373-392`）；底部一对 `OutlinedButton.icon`（刷新 / 更多）。
- 问题：chip 高度 34–36 < 44 且无按压反馈；选中靠底色 + `w600`，没有形状或图标区分；主色竖条标题是常见模板元素。
- 建议：chip 视觉高 32 但点击区撑到 44（外层 `SizedBox(height: 44)` 居中）、圆角 16（全胶囊）、水平 padding 12、Subheadline 15；选中 = 填充 accent 15% + accent 文字 + semibold。星期切换是互斥的 7 选 1，可用可横滑的分段控件。去掉竖条，标题用 Title3 20 semibold。

### 1.3 漫画详情页

**`lib/pages/comic_details_page/comic_page.dart`**
- 现状：
  - 顶栏动作（`:805-848`）：最多 6 个 `IconButton`。
  - 封面圆角 14（`:913`）；标题 `titleLarge / titleMedium`、`height 1.2`。
  - 阅读按钮（`:1000-1070`）：`FilledButton / OutlinedButton`，圆角 14，高 52，间距 10，文字 14 w600，图标 19；宽屏放大到 16 / 24，列宽 220。
  - 动作按钮 `_ActionButton`（`:2032-2112`）：圆角 12、`minHeight 44`、水平 padding 14、图标 19、`w600`；激活 = `primaryContainer` 底 + `primary` 图标 + 实心图标。
  - 信息条（`:1241-1270`）：padding 12 / 9、圆角 12、图标 18、`bodySmall`。
  - 标签（`:1376-1445`）：圆角 12、padding 16 / 6（约 32 高）；组标题 10 色轮换。
  - 分区头 `_ComicSectionHeader`（`:1952-2030`）：34×34 圆角 10 的图标底板 + `titleMedium w700`。
  - 分区胶囊圆角 20（`:1771, 1822`）；面板 margin 16 / padding 14 / 圆角 14。
  - 回顶 `FloatingActionButton`（`:423`）；骨架屏 `Colors.grey.shade700 / Colors.white`（`:3254`）。
- 问题：
  - 一页内圆角 10 / 12 / 14 / 20 四档并存。
  - 顶栏 6 图标超出 HIG 建议（导航栏尾部 1–2 个，其余进菜单）。
  - 主按钮文字 14pt 偏小；间距 10 不在 8pt 栅格上。
  - 彩虹标签把颜色当装饰，同一颜色在不同漫画里指向不同分类，违反"同色同义"。
  - 图标底板式分区头是模板感来源。
  - 骨架屏硬编码灰/白，深色下与表面色不协调。
  - `_ActionButton` 的激活态三重表达是全 App 做得最好的，可作范式推广。
- 建议：
  - 顶栏只留"分享"和"更多"（下拉菜单收纳清理/下载/刷新等）。
  - 封面圆角 12；主按钮高 50、圆角 12、文字 Headline 17 semibold、图标 20；两按钮间距 8 或 12。
  - 动作按钮保留结构，统一圆角 12、间距 8。
  - 标签统一用三级填充色 + 主文字色，组标题改为同行左侧的次级色文字（Footnote 13），不再着色；标签点击区 ≥ 36 高、组内间距 8。
  - 分区头改纯文字 Title3 20 semibold，去掉图标底板。
  - 回顶按钮改为顶栏标题点击回顶（iOS 惯例是点状态栏）或 44×44 圆形玻璃按钮。
  - 骨架屏颜色走令牌（如 `fillTertiary`）。

**`lib/pages/comic_details_page/chapters.dart`**
- 现状：多选工具栏含关闭、全选、反选、标记已读、标记未读 5 个 `IconButton` 加 `PopupMenuButton(more_vert)`（`:225-305`）；普通工具栏 5 个图标（排序、倒序、视图等，`:335-400`）；章节格圆角 10，定位态 `primaryContainer`；角标 10pt、左上/右下圆角 10（`:581-596`）；分组用 `AppTabBar`。
- 问题：工具栏图标过多且全是无标签图标；角标 10pt 低于 11pt 下限；`more_vert` 是 Android 图标。
- 建议：工具栏保留"排序 + 更多"，其余进下拉菜单（菜单项带文字 + 图标）；多选态改为底部工具栏放文字按钮；角标 Caption2 11。网格的列数与间距受测试约束，见 C 节。

**`lib/pages/comic_details_page/favorite.dart` / `actions.dart` / `comments_page.dart`**
- 现状：收藏夹选择用 `CheckboxListTile`（前置复选框）+ `Divider(indent 16)` + `s14 w600` 组标题；阅读模式等用 `RadioListTile` 对话框（`actions.dart:408-451`）；评论输入框圆角 24、0.6 边框；点赞/回复胶囊圆角 16、padding 12 / 4（约 24–28 高）、图标 16（`comments_page.dart:347-430`）；投票箭头 18。
- 问题：方形复选框和圆点单选是 Material 形态，iOS 用行尾对勾；点赞/回复点击区不足 44。
- 建议：单选/多选统一为"行 + 尾部 checkmark（accent 色）"，行高 44；点赞/回复视觉保持小胶囊，但点击区扩到 44×44（透明 padding）。评论区视觉受 golden 约束，见 C 节。

### 1.4 阅读器

**`lib/pages/reader/scaffold.dart`**
- 现状：
  - 外壳动画 140ms。
  - 顶栏（`:372-470`）：`BlurEffect`（blur 15）+ `surface` 92%（glass 模式 55%），底边 `Colors.grey.toOpacity(0.5)` 0.5 线；标题 `s18`，章节 `s16`，副信息 `s12`；右侧评论/下载/翻译/设置 4 个 `IconButton`。
  - 底栏（`:1084-1112`）同款；内含 `CustomSlider`、上一章/下一章 13pt 文字（`:1034-1057`）、页码 11pt（`:1010`）。
  - 底部功能键 `_ReaderBottomLabeledButton`（`:1730-1762`）：图标 22 + 标签 11，垂直 padding 4，水波纹圆角 8。
  - 悬浮翻章键（`:1553-1595`）：58×58、圆角 16、`elevation 2`。
  - 翻译进度条（`:151-190`）：`elevation 4`、圆角 18、padding 10 / 7、`s12`，错误文字 11。
  - 自动翻页条（`:1176-1215`）：高 48，`remove / add` 图标键 + 40 宽数值 + `TextButton`。
  - 电量/时钟 14pt，低电量 `Colors.red`。
  - 选图提示 232×42、圆角 8、`Colors.black.withAlpha(50)`。
- 问题：
  - 阅读器外壳是最该用 Liquid Glass 的地方（控件浮在图像内容上），现在是两条贴边的半透明矩形条加灰线。
  - 灰线、红色、黑遮罩硬编码。
  - 上一章/下一章点击区过小；页码 11pt 且紧贴滑块。
  - `elevation 4` 的翻译条和 `elevation 2` 的翻章键是 Material 阴影。
  - 玻璃透明度由用户设置 `ui_style` 切换，同一 App 两套材质。
- 建议：
  - 顶部：左右各一组 44×44 圆形玻璃按钮（返回；更多），标题居中用 Subheadline 15 semibold，下方章节名 Caption1 12；评论/下载/翻译收进"更多"菜单或底部功能行。
  - 底部：一个离底边 8、左右 16 的浮动玻璃胶囊（圆角 22），内含滑块行（两端是 44×44 的上一章/下一章图标键 `chevron.left / right`）和功能键行（每格 ≥ 44×44，图标 22，标签 Caption2 11）。
  - 材质：图像背景明暗不定，用 regular 档（约 blur 30 + 表面色 60–70%）；仅在 iOS 26+ 且未开"降低透明度"时启用，其余回退到 92% 不透明。去掉 `ui_style` 分叉，改为跟随系统无障碍设置。
  - 悬浮键与翻译条改玻璃底，去掉 `elevation`。
  - 动画 250ms、`easeOutCubic`；开"减弱动态效果"时改纯淡入淡出。

**`lib/pages/reader/gesture.dart`**
- 现状：点击翻页区左右各 30%（`_kTapToTurnPagePercent = 0.3`），中间 40% 呼出外壳；双击窗口 200ms；长按 250ms；拖动阈值 20px。
- 问题：视觉重构不应动这些数值；但长按、翻章没有触感反馈（全 App `HapticFeedback` 只有 6 处）。
- 建议：数值保持不变；只加 `HapticFeedback.selectionClick`（翻章边界、长按触发、滑块吸附）。

**`lib/pages/reader/reader.dart` / `continuous_mode.dart`**
- 现状：阅读背景 `Colors.white / Colors.black`（`reader.dart:885-889`）；连续模式里有圆角 8 的提示块和圆角 16 的自绘件（`continuous_mode.dart:1095, 2293-2304`）。
- 问题：阅读背景是内容，纯黑/纯白合理；提示块圆角与外壳不统一。
- 建议：背景不动；提示块圆角对齐令牌（12 / 16）。连续模式的几何计算有多组测试覆盖，只改颜色和圆角，不改尺寸。


### 1.5 收藏体系（`lib/pages/favorites/`）

**`shelf_page.dart`（书架主入口）**
- 现状：
  - 顶部（`:66-108`）：48 高的行内放默认 Material `TabBar`（下划线指示器），标签 `'收藏' / '網絡收藏' / '足跡'` 是写死的繁体字符串；右侧"緩存中心"胶囊：padding 12 / 6、圆角 16、`primaryContainer`、图标 16、文字 12。
  - 二级工具条（`:404-450`）：高 44；左侧文件夹名 16 / w600 + `arrow_drop_down` 20；排序图标 22，左右 padding 8；"編輯/完成"文字 13 / primary，`InkWell` 无 padding。
  - 文件夹选择用 `showModalBottomSheet` + `ListTile` + `Icons.check`（`:239-256`）；排序用 7 个 `RadioListTile` 的对话框（`:329-370`）。
  - 封面占位圆角 6。
- 问题：
  - "编辑"点击区约 18×44、排序约 38×44，都低于 44×44。
  - 下划线 `TabBar` 与胶囊按钮风格冲突；三个子视图是同一区域内的切换，HIG 推荐用分段控件。
  - 写死繁体字绕过了翻译系统，简中和英文用户看到的是繁体。
  - `arrow_drop_down` 是 Material 下拉箭头。
  - 排序要点开一个 7 项单选对话框，iOS 惯例是下拉菜单，当前项带对勾。
- 建议：
  - 顶部改 `VeneraSegmentedControl`（高 36 视觉 / 44 点击区，水平边距 16），"缓存中心"移到导航栏右侧，用 44×44 图标按钮（`arrow.down.circle`）。
  - 二级行：文件夹名 Headline 17 semibold + `chevron.down` 13，整块点击区 ≥ 44；排序改下拉菜单（`MenuAnchor` / 原生 pull-down），已改过排序的状态用实心图标 + accent 色表达；"编辑"改 `TextButton`，最小 44×44，Body 17。
  - 标签字符串走 `.tl`。

**`favorites_page.dart` / `side_bar.dart`（收藏夹页与文件夹侧栏）**
- 现状：窄屏用 `Icons.menu` 汉堡键打开抽屉，遮罩 `black 36%`、200ms；侧栏头 56 高、`s18`；文件夹行 padding 8 / 4 / 12 / 4，选中用 2px 边框 + 底色（`:196-233`）；缩进每级 14（最多 6 级）；展开键 28×28 `IconButton`（`:284-291`）；计数徽标圆角 11；云同步行 56 高、0.6 边框、`Icons.settings`。
- 问题：汉堡菜单不是 iOS 惯例；展开键 28×28 低于 44；选中态用 2px 描边属于"边框高亮"，在 iPadOS 侧栏里不常见。
- 建议：窄屏把文件夹列表作为导航栈的上一级（列表 → 推入文件夹），或用导航栏标题下拉；宽屏保持可隐藏侧栏，但选中改为整行 accent 15% 填充、圆角 10、accent 图标 + semibold 文字。展开键视觉 20，点击区 44。行高 44，每级缩进 16。保留 tooltip 文案，见 C 节。

**`local_favorites_page.dart` / `network_favorites_page.dart`**
- 现状：本地页顶栏有排序、筛选、搜索、多选 4 个 `IconButton`（`:610-685`）；筛选结果用 Material `InputChip`（`:1206`），行尾用 `FilterChip`（`:1156`）；空状态图标 48；网络收藏行图标 28 + 文字 16 / w500 + 删除 `IconButton` + `Icons.arrow_right`（`:379-410`）；多选态 `Icons.close` 作 leading。
- 问题：`InputChip` / `FilterChip` 是 Material 形态；`arrow_right`（实心三角）不是 iOS 的披露指示；顶栏图标偏多。
- 建议：顶栏保留"搜索 + 更多"，排序和筛选进菜单；筛选标签改自绘胶囊 token chip（高 32、圆角 16、三级填充、尾部 `xmark` 14，点击区 44）；所有 `Icons.arrow_right` 换 `chevron_right`（17pt、三级文字色）。

**`folder_widgets.dart` / `folder_actions.dart` / `favorite_actions.dart`**
- 现状：`_FolderCard` 圆角 12、内封面圆角 8、padding 8、`s14 w600` 标题、元信息 `s12` + 14pt 图标（`:15-135`）；面包屑是 `TextButton` + `chevron_right` 18（`:338-358`）；文件夹选择器 `PopupMenuItem` + `arrow_drop_down`（`folder_actions.dart:19-67`）；批量对话框固定 520×600（`favorite_actions.dart:142-146`）。
- 问题：固定 520×600 对话框在 iPhone SE（375×667）上几乎全屏且不可拖动关闭；卡片标题 14 偏小。
- 建议：批量操作改 sheet（large 档）；卡片标题 Subheadline 15 semibold、元信息 Caption1 12；面包屑保留 `TextButton`（被测试查找），只改样式。

### 1.6 分类 / 搜索

**`categories_page.dart`**
- 现状：分组 chips 行高 54，padding 12 / 8 / 12 / 2（`:331-362`）；chip 圆角 `controlRadius 16`，选中 primary 14% 底 + 34% 边 + `w700`；子项 chip 固定宽 66 / 72、垂直 padding 7、圆角 12（`:434-495`）；分组间 `Divider(height: 24)`；错误态 `FilledButton('重試')` 写死繁体。
- 问题：固定宽 66 的 chip 在长分类名和大字号下会截断；chip 约 30 高，点击区不足；顶部 chip 圆角 16 与子项 12 不一致。
- 建议：改成可换行的 `Wrap`，chip 最小宽 64、高 32、圆角 16（统一胶囊）、点击区 44；选中 = accent 填充 15% + accent 文字 + semibold（再加一个 12pt `checkmark` 作为非颜色线索）；分组标题 Footnote 13 大写次级色，间距 24，不用 `Divider`。

**`search_page.dart`**
- 现状：大量 `ListTile`（`contentPadding: zero`），leading 用 `Icons.search / link / history / hub_outlined`，trailing 用 `Icons.arrow_right` 或 `settings`（`:268-625`）；源选择用 `OptionChip`（圆角 8、padding 16 / 6）；联想防抖 120ms。
- 问题：搜索页没有用 iOS 的"搜索框在导航栏 + 取消按钮"模式；历史记录无左滑删除；`OptionChip` 圆角 8 与其他 chip 不一致。
- 建议：顶部搜索框（高 36、圆角 10、三级填充、`magnifyingglass` 17）+ 右侧"取消"文字按钮（Body 17、accent）；最近搜索做成分组列表（行高 44），支持左滑删除；源范围选择改为 scope bar（`VeneraSegmentedControl`）或可横滑胶囊。

**`search_result_page.dart`**
- 现状：顶栏有多选（`checklist`）和两个 `filter_alt_outlined` 按钮（`:596-620`）；筛选用 `showModalBottomSheet`，里面是 `FilterChip` 网格，标题 w700，底部全宽 `FilledButton`（`:495-580`）。
- 问题：两个同图标按钮（一个是搜索选项，一个是筛选）无法区分；`FilterChip` 是 Material 形态。
- 建议：合并成一个"筛选"入口（`line.3.horizontal.decrease.circle`），sheet 内用分组标题（Footnote 13）+ 统一 chip；底部按钮高 50、圆角 12；sheet 顶部左"重置"、右"完成"。

**`aggregated_search_page.dart`**
- 现状：结果占位块圆角 8、`surfaceContainerLow`（`:186-196`）；源标题是 `ListTile`；错误行 `Icons.error_outline` + 单行文字；超时 20s。
- 问题：每个源一个 `ListTile` 标题加一行横向封面，与首页分区同一模板；错误只有图标加文字，没有重试入口（未核实是否有其他入口）。
- 建议：与首页分区统一（Title3 标题 + 右侧"更多"），封面占位圆角对齐 `coverRadius`（见 A 节）；错误行加"重试"文字按钮。

### 1.7 社区

**`community/community_page.dart`**
- 现状：
  - 顶部 `TabBar` 包在 `controlRadius` 圆角容器里，指示器是 primary 16% 的 13 圆角块、`w700`（`:43-66`），视觉上已模仿分段控件。
  - 发帖 `FloatingActionButton`，`elevation 0`，圆角 16（`:285-296`）。
  - `PostCard`（`:329-420`）：`sectionRadius 16` 卡片，垂直 padding 5、内 padding 12；作者 13 / w600、时间 11 / `outline`、来源 12；`PopupMenuButton(more_vert 18)`；正文默认字号，`maxLines 5`；漫画缩略图 64×64、圆角 6、标题 10pt。
  - 选择漫画对话框里，类型标签 11pt、圆角 4。
- 问题：
  - FAB 是 Material 招牌控件；iOS 惯例是导航栏右侧的"撰写"按钮（`square.and.pencil`）。
  - 卡片列表"卡片套缩略图卡片"，每帖都是带边框的 16 圆角卡，信息流显得重。
  - 10pt 和 11pt 文字低于下限；`more_vert` 18pt 点击区不足。
  - `TabBar` 模拟分段控件，但没有用统一组件 `VeneraSegmentedControl`。
- 建议：
  - 发帖入口移到导航栏右侧，44×44。
  - 信息流改为全宽行 + 0.5 发丝分隔线（左侧缩进到正文起点），去掉卡片边框；作者 Subheadline 15 semibold、时间 Footnote 13 次级色、正文 Body 17、行距 1.35；缩略图 64×86（保持漫画比例）、圆角 8、标题 Caption1 12。
  - 更多按钮用 `ellipsis`，点击区 44×44。
  - 顶部换成 `VeneraSegmentedControl`。

**`community/post_detail_page.dart`**
- 现状：正文 15 / `height 1.5`（`:210`）；作者行 w600 + 时间 12 `outline`；点赞是裸 `InkWell`，图标 16；浏览量图标 16；关联漫画用 `Card` + `ListTile`，封面 42×56 圆角 6，`chevron_right`；楼层回复缩进 `indent * 20`，昵称 12 / w600，楼层号 `indent == 0 ? 12 : 10`，回复操作 11pt 和 12pt 图标（`:368-430`）；底部输入栏有 `close` 和 `send` 两个 `IconButton`。
- 问题：嵌套回复字号降到 10–11pt；缩进 20/级在 3 级以上挤占正文；回复、点赞点击区约 16–20pt；`Card` 默认阴影 + `elevation`，与其余平面风格冲突。
- 建议：正文 Body 17；回复昵称 Subheadline 15、内容 Body 17、元信息 Footnote 13；嵌套最多显示 2 级（第 2 级缩进 16 + 左侧 2px 竖线），更深层折叠为"查看 N 条回复"；操作按钮点击区 44；关联漫画改分组列表行（无阴影）；输入栏用圆角 18 的胶囊输入框 + 发送按钮（禁用态 30% 不透明度）。

### 1.8 设置

**`settings/settings_page.dart`**
- 现状：宽屏左栏 232 + `VerticalDivider`；搜索框用 `TextField` + `controlRadius` 圆角，聚焦时 primary 55% / 1.2 边框（`:237-275`），图标 20；页标题 `enableTwoViews ? 22 : 24`、w600（`:326`），返回键 `Icons.arrow_back`；分类 `ListTile`：圆角 9、padding 12、选中 `primaryContainer 45%`、图标 21、标题 14、副标题 12、trailing `chevron_right 18`（`:407-431`）；组标题 12 + 顶部间距 28；分组背景 `colors.surface`、圆角 12。
- 问题：分类列表在 iOS 上应是带彩色圆角图标的分组列表（Settings.app 惯例），现在是单色 21pt 图标；标题 14 / 副标题 12 偏小；选中态只靠底色；22 / 24 两套页标题字号。
- 建议：
  - 分类行高 44（有副标题时 ≥ 56）、标题 Body 17、副标题 Footnote 13；leading 用 29×29、圆角 7 的彩色方块 + 白色 17pt 图标。这里用色是为了识别分类、颜色固定，不违反同色同义。
  - 宽屏选中 = accent 填充 + 白字（iPadOS 侧栏惯例）或 accent 15% + semibold，二选一全 App 统一。
  - 页标题手机用 Large Title 34 bold，宽屏 Title1 28 bold。
  - 搜索框聚焦不加彩色描边，只显示"取消"按钮。

**`settings/settings_layout.dart`**
- 现状：页标题 `headlineMedium` 27 / w600（`:82-84`），副标题 13；组标题 13 `onSurfaceVariant`，`left 4 / bottom 9`（`:196-206`）；分组 `Material(shape: RoundedRectangleBorder(radius 12, side outlineVariant 65% / 0.7))`，背景 `colors.surface`；行 padding 16 / 14、图标 21、标题 14、副标题 12、`chevron 18`；行间 `Divider(indent 16, endIndent 16)`；宽屏两列加 `VerticalDivider(width 1, thickness 0.6)`；组间距 24。
- 问题：
  - 结构已是 iOS inset grouped，但分组底色 `surface` 与页面 `scaffoldBackgroundColor = surface` 相同，只能靠 0.7 描边分层。iOS 是靠灰底白卡分层，无描边。
  - 分隔线 `endIndent 16` 不符合 iOS（右侧应通到边）；左缩进应对齐文字起点（有图标时为 16 + 图标宽 + 间距），而不是固定 16。
  - 27pt 是非标准字号；`bottom: 9` 不在 8pt 栅格上。
  - 宽屏两列加竖线不是 iOS 形态。
- 建议：页面背景 `groupedBackground`（`#F2F2F7 / #000`），分组 `secondaryGroupedBackground`（`#FFF / #1C1C1E`），圆角 10（iOS 26 为 12 也可，全局统一），去掉描边；组标题 Footnote 13、左 16、下 8；行最小高 44、padding 水平 16 / 垂直 11；分隔线 0.5、`separator` 色、左缩进到文字起点、右侧 0。注意：`Material + RoundedRectangleBorder` 这一层被测试用来定位分组，必须保留（只改颜色、圆角数值和 side）。

**`settings/setting_components.dart`**
- 现状：`_SwitchSetting` 用 `ListTile` + Material `Switch`（`:60-75`）；下拉设置 trailing `Icons.arrow_drop_down`，手机用 `showModalBottomSheet`（标题 18 / w600，padding 20 / 0 / 20 / 16，`ListTile` + `Icons.check`），桌面用 `PopupMenuItem`（`elevation 3`）（`:320-430`）；`_SliderSetting` 用 `ListTile` + `Slider` + `s12` 数值；排序列表项 `BoxShadow(black12, blur 5)`（`:806`）；空态图标 64、`s16`；帮助按钮 18pt `help_outline`。
- 问题：Material `Switch` 在 iOS 上形态不对（M3 带拇指图标、轨道较宽）；下拉用 `arrow_drop_down` 和底部 sheet，iOS 惯例是行尾显示当前值 + `chevron.up.chevron.down`，点开 pull-down 菜单；拖拽项 `black12` 阴影在深色下不可见；帮助按钮点击区小。
- 建议：iOS 上用 `Switch.adaptive` 或 `CupertinoSwitch`（宽 51、高 31、accent / 系统绿）。`_SwitchSetting` 内部仍需是 `Switch` 类型，测试按 `find.byType(Switch)` 查找，`Switch.adaptive` 满足这一点，`CupertinoSwitch` 不满足。下拉改"值（次级色 Body 17）+ `chevron.up.chevron.down` 13" + 菜单；滑块数值放行尾，用等宽数字；拖拽阴影用令牌 `shadowLift`（见 A 节）。

### 1.9 共享组件（`lib/components/`）

| 文件 | 现状（具体参数） | 问题 | 建议 |
|---|---|---|---|
| `button.dart` `Button` | `GestureDetector` + `AnimatedContainer` 160ms；`minWidth 76 / minHeight 32`；圆角 16；文字 14；hover 时 `black 10%` blur 2 y1 阴影 + 90% 色；outlined 0.6 边框；loading 16×16 / 1.8 圈 | 高度 32 < 44；触屏无按压态；有阴影；圆角 16 与高度 32 组合等于全胶囊 | `minHeight 44`（紧凑 36，但点击区扩到 44）、圆角 12、文字 Headline 17 semibold（紧凑 Subheadline 15）；按压态 = 不透明度 0.6 或 0.97 缩放，100ms；去阴影；loading 用 `CupertinoActivityIndicator`（iOS） |
| `button.dart` `_IconButton` | padding 6 + 图标 24 = 36×36；hover 底色 `outlineVariant 40%`，圆形 | 36 < 44，无按压态 | 外框 44×44，图标 22，按压 0.6 不透明度 |
| `button.dart` `MenuButton` | `IconButton`，`fixedSize 48×48`，`more_horiz` | 尺寸被测试断言为 48，见 C 节 | 只换图标与颜色，尺寸保留 48 |
| `ios_design.dart` `VeneraSegmentedControl` | 外 padding 3、段高 34、外圆角 16 / 内 13；选中 primary 16% 底 + primary 字 + w700；180ms；`InkWell` | 方向正确；但 iOS 分段控件的选中段是白（深色下灰）色"滑块" + 阴影，不是 accent 着色；水波纹不对；不支持大字号增高 | 段高 32，外 padding 2、外圆角 9 / 内 7（或胶囊，iOS 26）；选中滑块 = `#FFFFFF / #636366` + `0 3 8 rgba(0,0,0,.12)`，文字主色 semibold；用一个 `AnimatedAlign` 滑块替代各段独立变色，250ms `easeOutCubic`；去 `InkWell` |
| `ios_design.dart` `VeneraIconButton` | 默认 44（首页传 52）；`controlRadius 16`；0.7 边框；`mutedText` 前景 | 默认 44 正确；带边框的方形底板是 Android "tonal" 观感 | 无底板 44×44（导航栏内）或圆形玻璃底板（浮层内）；按压 0.6 不透明度 |
| `appbar.dart` `Appbar` / `SliverAppbar` | 高 52；leading `Icons.arrow_back`；间距 8 / 16；标题 20；shadow 样式滚动后 `elevation 2`；blur 样式滚动后 blur 15；背景 `surface 86%` | Android 返回箭头 + 左对齐 20pt 标题；52 非标准 | iOS：高 44，`chevron_left` 22 +（可选）上一页标题，标题居中 Headline 17 semibold；滚动后才显示材质 + 0.5 发丝线；去 elevation；支持大标题变体（96 → 44） |
| `appbar.dart` `AppTabBar` | 高 48；tab padding 6 / 6 + 内水平 16；圆角 8；文字 w500，选中仅变 primary；`_IndicatorPainter` 下划线；`TabPageSelectorButton` 48×48，`format_list_bulleted_rounded`；trailing 左侧 0.6 竖线 | 选中只靠颜色；有效点击高 36 | 选中 = semibold + accent + 2.5px 圆头下划线（或胶囊底）；外框 44 高、tab padding 水平 12；`_kTabHeight` 与选择器尺寸受测试约束，见 C 节 |
| `appbar.dart` `TabActionButton` | 圆角 8，图标 20 primary | 对齐即可 | 圆角 10 |
| `search_field.dart` `AppSearchField` | 手机默认 52 / 桌面 46，`toolbarHeight = 40`；圆角 `min(16, h/2)`；图标 `Icons.search` 24、左 16 间距 8；提示 `s16`；iOS 上 `glassSurface` + blur 18 | 52 过高；24pt 图标偏大；内容层玻璃 | 默认 36（导航栏内）/ 44（页面内）；圆角 10；图标 17，左 8 间距 6；提示 Body 17，`placeholder` 色；底色 `fillTertiary`，非玻璃。`toolbarHeight` 常量受测试约束 |
| `select.dart` `Select` | 外框 `outlineVariant` 1px、圆角 4；`showMenu(elevation 3, color F6F6F6 / 1E1E1E)`；文字 `s14`；`arrow_drop_down` primary；padding 12 / 4 | 硬编码菜单色；圆角 4 为全 App 最小；Material 下拉 | 无边框，"值 + `chevron.up.chevron.down`"；菜单用统一 `MenuAnchor` 主题（圆角 14、厚材质、行高 44） |
| `select.dart` `FilterChipFixedWidth` / `OptionChip` | 圆角 8；padding 12 / 8 或 16 / 6；`labelLarge`；`AnimatedCheckIcon` | 与分类页 chip（12 / 16）、首页 chip（20）四种圆角 | 统一 `VeneraChip`：高 32、圆角 16、点击区 44、选中三重表达（填充 + 字重 + 对勾） |
| `menu.dart` | 手机 `showModalBottomSheet(showDragHandle, maxWidth 560, 90% 高)`；桌面 `_DesktopMenu`：项 `minimumSize(0, 44)`、padding 14 / 10、字 15、图标 20、`Divider(height 12)`、圆角 8、宽 ≤ 272 | 桌面菜单参数基本合规；手机端长按菜单一律底部 sheet，iOS 惯例是上下文菜单（预览 + 菜单） | 手机 iOS：长按封面用 `CupertinoContextMenu` 风格（预览封面 + 圆角 14 菜单，行高 44，破坏性项红色置底）；sheet 仅用于复杂操作。`context_menu_test` 断言手机上出现 `BottomSheet`，见 C 节 |
| `mobile_menu.dart` | 菜单按钮 `TextButton` `minimumSize(0, 48)`、字 14、圆角 10；主操作 `FilledButton` 高 54、圆角 14、字 15；快捷格 68 高、圆角 12、字 13；头部 42×56 封面 + 16 / w500 标题 | 三种圆角（10 / 12 / 14）、三种字号 | 统一圆角 12，行高 44 / 主按钮 50，字号 Body 17 / 快捷格 Caption1 12 |
| `flyout.dart` | 遮罩 `black 30%`；`FlyoutContent` 圆角 8、padding 16 / 8、标题 bold 16 | 是自绘 popover；iOS 紧凑宽度下 HIG 不建议用 popover | 紧凑宽度改 alert 或 sheet；常规宽度用圆角 14 厚材质 popover |
| `message.dart` toast `_ToastOverlay` | 距底 24 + 键盘；`inverseSurface`；圆角 8；`elevation 2`；字 16 / w500；2s | Material snackbar 观感；底部会被 iOS 浮动标签栏遮挡（未核实） | 顶部或标签栏上方的胶囊 HUD：圆角 22（全胶囊）、厚材质、Subheadline 15 semibold、图标 17、无 elevation；位置用原生栏回报的高度 |
| `message.dart` `ContentDialog` 等 | `ContentDialog`：圆角 8、`elevation 2`、200ms、关闭 `IconButton(Icons.close)` 做 leading；`showDialogMessage / showConfirmDialog` 用 `FilledButton` | 圆角 8 对话框 + 左上关闭 X 是 Material 全屏对话框形态 | iOS alert：宽 270、圆角 14、厚材质；标题 Headline 17 semibold、消息 Footnote 13；按钮行高 44、分隔线 0.5，取消在左、主操作在右（semibold），破坏性用红色。复杂内容用 sheet（左"取消"右"完成"） |
| `pop_up_widget.dart` | `PopUpWidget`：圆角 12，白色 alpha 50 / blur 10 阴影，遮罩 `black54`，220ms；`PopUpWidgetScaffold` 头部 56 高、`Icons.arrow_back_sharp`、标题 22 / w500、背景 `surfaceTint` 20 alpha | 白色发光阴影；`arrow_back_sharp`；染色头部 | 改 sheet 头：高 56、拖动条、标题居中 Headline 17、左"取消"/返回 `chevron_left`、右"完成"；遮罩 `black 20–30%` |
| `comic.dart` `ComicTile` | 详细模式：封面 `secondaryContainer`、圆角 8、阴影 `outlineVariant` blur 1 y1；外 padding 12 / 6；内 padding 8 / 8 / 14 / 8；标题 `maxLines 2`。简略模式：阴影 `black 20%` blur 2 y2、圆角 8；标题 w500、padding 4。角标：收藏 24×24 `Colors.green`、稍后读 `Colors.orange`、语言 `Colors.blue 90%`；页码 `black 50%` 圆角 8；集数徽标 `Colors.blue 72%` 圆角 6；收藏集标记 `black 55%` 圆角 6 | 两种模式两种阴影；角标三种硬编码饱和色，深色下刺眼；同屏 6 / 8 两种圆角 | 封面统一：圆角 8（≤ 120 宽）/ 10（> 120 宽）；去阴影，改 0.5 内描边 `rgba(0,0,0,.08)`（深色 `rgba(255,255,255,.1)`）；角标统一为左上 20×20 圆形、`black 55%` + 白色 SF 图标，或用系统语义色（green / orange / blue 的动态值）；集数/页码徽标统一 Caption2 11 semibold、圆角 6、`black 55%` |
| `simple_comic_tile.dart` | 98×136；圆角 `cardRadius 10`；角标 24×24、图标 16 / 15；标记 padding 3、圆角 6、图标 12；标题 `bodySmall w500` | 与 `ComicTile` 的 8 不一致；12pt 图标标记太小 | 与 `ComicTile` 同一套 `coverRadius`；标题 Footnote 13 medium、2 行；封面与标题间距 6 → 8 |
| `comic_grid.dart` | 多选：`secondaryContainer 72%`、圆角 12、margin 4、150ms | 选中只靠底色 | 选中 = 封面右下 22pt 实心 accent 圆形对勾（未选为空心圈）+ 封面 0.85 不透明度遮罩；保留底色可选 |
| `comic_list.dart` | 多选顶栏 `close / select_all / deselect` 三个 `IconButton`；`FilledButton`；错误态 `error_outline` + `OutlinedButton` | 多选是 Material 上下文操作栏模式 | iOS：导航栏左"全选"、右"完成"，底部工具栏放操作（文字按钮） |
| `rating.dart` | `StarRating` 自绘星，被 `GestureDetector` 包裹；详情页 size 24 | 交互星星每颗 24pt，点击区不足；无触感 | 每颗视觉 22、点击区 44，间距 4；评分变化时 `selectionClick` |
| `swipe_action.dart` | `SwipeActionTile` `extentRatio` 可变；默认背景 `colorScheme.error` | 破坏性红色用 error 合理 | 动作按钮最小宽 74（iOS 惯例），图标 + Caption1 标签；全滑触发时加触感 |
| `loading.dart` | `NetworkError`：图标 28、padding 16、内块圆角 8 / padding 12、`OutlinedButton`（`onPrimaryContainer 50%` 边）、字 12、`FilledButton` 重试；`ListLoadingIndicator` 高 80；`FiveDotLoadingAnimation` 1200ms | 错误态按钮三种样式混用；自绘五点动画非 iOS | 错误态：SF 图标 44 + Title3 20 标题 + Body 17 说明（次级色）+ 一个主按钮（50 高、圆角 12）+ 一个次级文字按钮；加载用 `CupertinoActivityIndicator`（iOS）/ 系统圈 |
| `side_bar.dart` | 见 1.1 | — | — |
| `effects.dart` `BlurEffect` | blur 15，`TileMode.mirror`，无色 | 只有模糊，没有饱和度提升与亮度调整，与 iOS 材质相比发灰；无"降低透明度"回退 | 新增 `VeneraMaterial(thickness: ultraThin/thin/regular/thick)`：blur 20 / 25 / 30 / 40，叠加表面色 45% / 60% / 72% / 85%；`MediaQuery.highContrast` 或平台通道读到"降低透明度"时切到不透明 |


---

## A. 全局设计系统应补齐的令牌

现有 11 个字段（`contentSurface / controlSurface / glassSurface / glassStrongSurface / borderSubtle / borderStrong / mutedText / controlRadius / cardRadius / sectionRadius / blurSigma`）只覆盖了"表面色 + 3 档圆角 + 1 个模糊值"。建议拆成多个 `ThemeExtension`（避免单个类字段过多导致 `lerp / copyWith` 难维护），全部挂在 `getTheme()` 的 `extensions` 上。保留 `VeneraDesignTokens` 原字段名不删，作为兼容层，内部改为从新令牌派生。

### A.1 间距栅格 `VeneraSpacing`（8pt 基准，带 4pt 半格）

| 令牌 | 值 | 用途 |
|---|---|---|
| `xxs` | 2 | 图标与角标微调 |
| `xs` | 4 | 图文紧贴、徽标内边距 |
| `sm` | 8 | 控件间距、chip 间距 |
| `md` | 12 | 卡片内边距、行内图标与文字 |
| `lg` | 16 | **页面水平边距（手机）**、行水平内边距 |
| `xl` | 20 | 页面水平边距（宽屏 ≥ 600） |
| `xxl` | 24 | 分区间距 |
| `xxxl` | 32 | 大分区、空状态上下 |
| `pageInset(context)` | 16 / 20 / 按可读宽度居中 | 替代现在 8 / 12 / 16 混用 |
| `readableWidth` | 672 | 宽屏正文最大宽（设置、帖子详情） |

### A.2 字号层级 `VeneraTypography`（映射 iOS text style，并写进 `ThemeData.textTheme`）

| 令牌 | 字号 / 行高 / 字重 | 对应 M3 slot | 替换 |
|---|---|---|---|
| `largeTitle` | 34 / 41 / bold | `displaySmall` | 设置页 27、导航大标题 |
| `title1` | 28 / 34 / bold | `headlineMedium` | 宽屏页标题 22 / 24 |
| `title2` | 22 / 28 / bold | `headlineSmall` | 详情页漫画名 |
| `title3` | 20 / 25 / semibold | `titleLarge` | 分区标题（`s18 w600`、`titleMedium w700`） |
| `headline` | 17 / 22 / semibold | `titleMedium` | 导航栏标题、主按钮 |
| `body` | 17 / 22 / regular | `bodyLarge` | 列表行标题（现 14） |
| `callout` | 16 / 21 / regular | `bodyMedium` | 正文段落（现 15） |
| `subheadline` | 15 / 20 / regular | `titleSmall` | chip、次级行 |
| `footnote` | 13 / 18 / regular | `bodySmall` | 副标题、分组标题（现 12–13） |
| `caption1` | 12 / 16 / regular | `labelMedium` | 元信息 |
| `caption2` | 11 / 13 / regular | `labelSmall` | 标签栏、角标（最小值，替代 10 / 9 / 8） |

规则：
- 禁止新增 `fontSize:` 字面量，`ts.sNN` 逐步迁移到上述令牌。
- 所有固定高度容器内的文字改用 `minHeight`，并在 `textScaler` 为 1.3 与 2.0 两档下验收。
- CJK 字体：iOS 上 `fontFamily` 为空，走系统 PingFang 即可。现有 Linux / Windows 的 Noto 回退链保留。

### A.3 触控与控件尺寸 `VeneraSizes`

| 令牌 | 值 | 用途 |
|---|---|---|
| `minTapTarget` | 44 | 所有可点元素的最小点击区（视觉可以更小） |
| `navBarHeight` | 44（大标题展开 96） | 导航栏 |
| `tabBarHeight` | 49（非 iOS 自绘时） | 底栏；iOS 用原生回报值 |
| `toolbarHeight` | 44 | 底部工具栏 |
| `rowHeight` | 44（双行 ≥ 60） | 列表行 |
| `buttonHeightLarge / Regular / Small` | 50 / 44 / 32（点击区仍 44） | 按钮 |
| `searchFieldHeight` | 36（栏内）/ 44（页内） | 搜索框 |
| `segmentHeight` | 32 | 分段控件 |
| `chipHeight` | 32 | chip |
| `iconSm / Md / Lg` | 17 / 22 / 28 | SF 风格图标 |
| `settingsIconTile` | 29（圆角 7） | 设置彩色图标块 |
| `coverAspect` | 98 / 136 ≈ 0.72 | 封面比例（已在用） |

### A.4 圆角 `VeneraRadii`（把 21 种取值收敛成 6 档）

| 令牌 | 值 | 用途 |
|---|---|---|
| `xs` | 6 | 角标、小徽标 |
| `sm` | 8 | 封面（≤ 120 宽）、小缩略图 |
| `md` | 10 | 列表选中底、搜索框、侧栏行 |
| `lg` | 12 | 按钮、分组列表、卡片、chip 容器 |
| `xl` | 16 | sheet 顶部、浮动面板 |
| `xxl` | 22 / `pill` = 高度 ÷ 2 | 阅读器浮动胶囊、toast、chip |
| `continuous` | bool | iOS 用连续曲率圆角（`ContinuousRectangleBorder` 系数约 2.3×，或接入 squircle 实现） |

现有字段映射：`controlRadius 16 → lg 12`；`cardRadius 10 → sm 8 / md 10`；`sectionRadius 16 → lg 12`。

### A.5 语义色 `VeneraColors`（每个都有 light / dark / 增强对比度三套值）

- 背景：`systemBackground / secondarySystemBackground / tertiarySystemBackground`；`groupedBackground / secondaryGroupedBackground / tertiaryGroupedBackground`。
- 文字：`label / secondaryLabel（60%）/ tertiaryLabel（30%）/ quaternaryLabel（18%）/ placeholder`。用来替代 `mutedText`，以及把 `colorScheme.outline` 当文字色的用法。
- 填充：`fill / secondaryFill / tertiaryFill / quaternaryFill`（搜索框、chip、骨架屏）。
- 线：`separator`（0.5px、半透明）、`opaqueSeparator`；替代 `borderSubtle / borderStrong / Colors.grey.toOpacity(0.5)`。
- 强调：`accent`（用户主题色的 iOS 化版本）、`accentFill15`（选中底）、`link`。
- 状态：`destructive / success / warning / info`（取 systemRed / Green / Orange / Blue 的动态值），替代 93 处 `Colors.red / green / orange / blue`。
- 媒体叠层：`overlayScrim`（`black 55%`，角标）、`dimming`（`black 35%`，HIG 建议的 clear 玻璃调光层）、`modalBarrier`（`black 20%` / 深色 `48%`）。
- 阴影：`shadowLift`（`0 4 16 rgba(0,0,0,.12)`，深色为 0 或改用 1px 高光描边），仅用于浮层与拖拽中项。

### A.6 材质 `VeneraMaterials`

| 令牌 | blur | 表面色不透明度（浅 / 深） | 用途 |
|---|---|---|---|
| `ultraThin` | 20 | 40% / 45% | 媒体上的 clear 玻璃（阅读器按钮） |
| `thin` | 25 | 55% / 60% | 导航栏滚动后 |
| `regular` | 30 | 70% / 72% | 阅读器栏、标签栏（非 iOS） |
| `thick` | 40 | 85% / 86% | 菜单、alert、侧栏 |
| `saturation` | 1.8 | — | 背景饱和度提升（`ColorFilter.matrix`），玻璃不再发灰 |
| `reduceTransparencyFallback` | — | 100% | 降低透明度开启时的回退 |

规则：材质只用于功能层（导航栏、工具栏、标签栏、浮动按钮、菜单、sheet、阅读器外壳），内容层（首页分区、搜索框、卡片）禁用。

### A.7 动效 `VeneraMotion`

| 令牌 | 值 | 替换 |
|---|---|---|
| `instant` | 100ms | 按压态（现 100×16） |
| `fast` | 150ms | 选中切换、徽标（现 140 / 150 / 160 / 180） |
| `standard` | 250ms | 外壳显隐、分段滑块、sheet（现 200 / 220 / 250） |
| `slow` | 350ms | 页面级 / Hero |
| `curveStandard` | `Curves.easeOutCubic` | |
| `curveSpring` | `SpringDescription(mass 1, stiffness 300, damping 30)` | 分段控件、sheet 回弹 |
| `reduceMotion` | 读取 `MediaQuery.disableAnimations` | 为 true 时位移动画改为 150ms 淡入淡出 |

### A.8 其他

- `VeneraHaptics`：`selection / lightImpact / success / warning` 四个封装，各端统一调用。
- `VeneraElevation`：只有 `none` 与 `floating` 两档，禁止 `elevation: 1–4` 字面量。
- `VeneraIcons`：一张 Material → SF 语义映射表（如 `arrow_back → chevron_left`、`more_vert → more_horiz`、`arrow_right → chevron_right`、`arrow_drop_down → expand_more`），iOS 上统一换成 SF 风格字形。注意 `pubspec.yaml` 中**没有** `cupertino_icons` 依赖，引入它算新增依赖；也可以只用 Material Symbols 的 rounded 系列做近似。

---

## B. 重构执行波次（按杠杆从大到小）

| 波次 | 内容 | 涉及文件 | 杠杆 / 理由 | 验收 |
|---|---|---|---|---|
| **0 令牌与主题** | 新增 A 节令牌扩展；`getTheme()` 改中性背景、iOS 系统色、补全 `textTheme` 与各组件主题（按钮 44 / 圆角 12、`iconButtonTheme` 44、`listTileTheme`、`dialogTheme` 14、`bottomSheetTheme`、`switchTheme`、`chipTheme`、iOS 去水波纹）；`VeneraDesignTokens` 原字段改为派生值 | `main.dart`、`ios_design.dart`、新 `design_tokens/*.dart` | 一次改动影响 82 个文件的 220 个 `IconButton`、48 个文件的对话框、全部 `ListTile` | 跑全部布局 / golden 测试，确认哪些需要更新基准（见 C） |
| **1 共享基础控件** | `Button` / `_IconButton`（44、按压态、去阴影）；`Appbar` / `SliverAppbar`（44、`chevron_left`、居中标题、滚动材质）；`AppTabBar` 选中三重表达；`AppSearchField`（36 / 44、去内容层玻璃）；`Select` / `OptionChip` / `FilterChipFixedWidth` 合并成 `VeneraChip`；`ContentDialog` / alert / toast；`BlurEffect` → `VeneraMaterial`；`VeneraSegmentedControl` 滑块化 | `button.dart`、`appbar.dart`、`search_field.dart`、`select.dart`、`message.dart`、`effects.dart`、`ios_design.dart`、`menu.dart`、`mobile_menu.dart`、`pop_up_widget.dart`、`flyout.dart`、`loading.dart` | 二级页全部复用；改完后页面层只需删掉局部覆写 | `app_search_field_test`、`menu_button_test`、`app_tab_bar_test`、`context_menu_test`、`pop_up_scaffold_bottom_inset_test` |
| **2 导航框架 + 封面卡片** | 顶栏改覆盖式大标题 + 动作收纳；非 iOS 底栏去药丸、去 22 圆角；侧栏 44 行高 + 厚材质；原生 `UITabBar` 高度回报；`ComicTile` / `SimpleComicTile` / `comic_grid` 统一封面圆角、去阴影、角标语义色、多选对勾 | `navigation_bar.dart`、`native_tab_bar.dart`、`AppDelegate.swift`、`side_bar.dart`、`main_page.dart`、`comic.dart`、`simple_comic_tile.dart`、`comic_grid.dart`、`comic_list.dart` | 每个一级页都在框架内；封面卡片在首页、收藏、搜索、分类、历史全部出现 | `navigation_bar_labels_test`、`home_comic_hero_test`、`local_library_ui_test`、`comic_description_row_test` |
| **3 核心一级页** | 首页（分区去卡片、边距 16、搜索行瘦身）；书架 / 收藏（分段控件、工具条 44、排序菜单、本地化）；详情页（顶栏收纳、按钮 50 / 12、去彩虹标签、分区头纯文字、去 FAB） | `home_page.dart`、`home_source_feed.dart`、`favorites/*`、`comic_details_page/comic_page.dart`、`chapters.dart`、`favorite.dart`、`actions.dart` | 用户停留时间最长；前两波的效果在这里集中体现 | `favorites_page_layout_test`、`chapter_card_layout_test`、`home_edit_back_gesture_test`、`shelf_navigation_regression_test`、`library_empty_state_test` |
| **4 阅读器外壳** | 顶部圆形玻璃按钮 + 居中标题；底部浮动玻璃胶囊（44 章节键、44 功能格）；去 `ui_style` 分叉改跟随系统；去 elevation；触感 | `reader/scaffold.dart`（只动 build 方法的视觉部分） | 视觉收益大，但逻辑密度最高，所以放在基础层稳定之后 | `reader_customizations_test`（源码字符串检查）、`reader_night_mode_button_test`、`reader_auto_page_turning_button_test`、`reader_back_swipe_test`、`continuous_reader_*` |
| **5 分类 / 搜索 / 设置** | 分类 chip 换行 + 统一；搜索页导航栏搜索框 + 取消 + 范围栏；结果页合并筛选；设置分组底色分层、44 行、彩色图标块、`Switch.adaptive`、下拉改菜单 | `categories_page.dart`、`search_page.dart`、`search_result_page.dart`、`aggregated_search_page.dart`、`settings/*` | 设置页结构已接近 iOS，改动以参数为主；但测试约束最密集 | `settings_redesign_layout_test`、`settings_navigation_test`、`settings_menu_order_test`、`settings_slider_save_test`、`customization_settings_test`、`reader_settings_search_test` |
| **6 社区 / 评论 / 叶子页** | 社区信息流去卡片、FAB 移到导航栏、字号 ≥ 11、嵌套回复折叠；评论组件（最后做，同时更新 golden）；其余约 100 个叶子页与对话框：`RadioListTile` / `CheckboxListTile` 换尾部对勾行，清理 `fontSize` 字面量与硬编码颜色 | `community/*`、`comments_page.dart`、`components/comment_*`、`rich_comment_content.dart`、其余 `lib/pages/**` | 单页影响小，按访问频率逐个推进即可 | 3 个评论 golden 测试（需重生成基准）、`comments_widgets_test`、`tasks_page_test`、`llm_provider_editor_layout_test` 等 |

每一波都要在浅色 / 深色、`textScaler` 1.0 / 1.3 / 2.0、320 / 390 / 626 / 1100 宽度下截图对比；iOS 17 与 iOS 26 真机各过一遍材质与原生标签栏。

---

## C. 视觉改动的高风险区（以及会撞上的测试）

> CI（`.github/workflows`，第 551 行）只跑 28 个测试，其中与 UI 相关的有：`home_comic_hero_test`、`llm_provider_editor_layout_test`、`settings_menu_order_test`、`settings_navigation_test`、`settings_scope_test`、`settings_slider_save_test`、`task_list_test`、`tasks_page_test`、`customization_settings_test`、`reader_customizations_test`。下列其余 widget / golden 测试不在 CI 里，但它们记录的是真实布局约束，重构时应在本地全跑。

| # | 风险点 | 具体约束（测试 / 代码位置） | 会撞上的改动 | 规避方式 |
|---|---|---|---|---|
| 1 | **主题工厂被测试直接调用** | `settings_redesign_layout_test.dart:170-176` 调 `const MyApp().createState().getTheme(Colors.purple, null, null, brightness)` | 改 `getTheme` 签名、改成异步、在里面读 `App` 或 `appdata` 的未初始化状态 | 签名与"纯函数"性质保持不变；新令牌只依赖传入的参数 |
| 2 | **设置分组的结构断言** | 同文件 `:352-378`：行的 `InkWell` 宽、左、右必须与祖先 `Material(shape: RoundedRectangleBorder)` 相等（±0.5）；`ValueKey('settings-category-$n')`；`find.byTooltip('Back'.tl)`；`textScale 1.3` 在 320 宽下无溢出；2560 / 1100 / 626 / 390 / 320 五种宽度 | 把分组换成 `Container + BoxDecoration`（找不到 `Material`）；行内加左右 margin（宽度不等）；去掉返回键 tooltip；行高写死导致 1.3 倍溢出 | 保留 `Material + RoundedRectangleBorder` 结构，只改颜色、圆角、`side: BorderSide.none`；行贴满分组宽度；返回键保留 `tooltip: 'Back'.tl` |
| 3 | **设置开关必须是 `Switch`** | `settings_navigation_test.dart:79-81`：`find.byType(Switch)` 且 `hitTestable`；`find.byType(TextField).first` 是搜索框 | 换成 `CupertinoSwitch`；搜索框改成非 `TextField` 的自绘输入 | 用 `Switch.adaptive`（类型仍是 `Switch`）；搜索框保持 `TextField` |
| 4 | **`settings_menu_order_test`（在 CI 中）** | 分类顺序、500 宽下不显示 `Appearance` 与 `settings-category-6`，1000 宽下显示 | 重排分类、合并分类、改两栏断点 | 不动分类顺序与 600 断点（`changePoint`） |
| 5 | **搜索框高度常量** | `app_search_field_test.dart:76-82`：在 52 高行内，高度等于 `AppSearchField.toolbarHeight`（当前 40）；清除键 `Icons.clear`、搜索图标 `Icons.search` 被 `byIcon` 查找 | 把 `toolbarHeight` 改为 36（可以，只要组件真按此值渲染）；把图标换成 `CupertinoIcons.search` / `xmark_circle_fill`（测试失败） | 视觉换成 SF 风格时保留 `Icons.search` / `Icons.clear` 的 `IconData`，或同步修改测试 |
| 6 | **`MenuButton` 48×48** | `menu_button_test.dart:30-32`：`find.byType(IconButton)` 尺寸等于 `Size.square(48)` | 改成 44 或换成非 `IconButton` | 保持 48（大于 44，合规） |
| 7 | **底部导航标签与图标** | `navigation_bar_labels_test.dart`：390 / 626 / 844 宽度下内容安全边界（`right = width - 28` 等，来自 `systemGestureInsets`）；iOS 变体下键盘弹出时 `HeroControllerScope` 不重建；标签文字 `findsOneWidget`（意味着同一标签不能同时出现在 tooltip 以外的第二处，例如顶栏标题 + 底栏标签）；按 `Icons.bookmark_outlined` 点击切页 | 横屏去掉 `sideInsets` 计算；顶栏标题与底栏标签用相同文字同时渲染；改 `PaneItemEntry` 图标字段语义；`NaviPaneState` 在 `build` 中订阅完整 `MediaQuery.of` | 保留 `sideInsets` 逻辑与 aspect 化的 `MediaQuery` 订阅（`:174-190`）；大标题不要和底栏标签用同一文本，或在测试场景下只有一个出现。注意：测试在 iOS 变体下不会创建 `UiKitView`（未核实），改原生栏时需同步确认 |
| 8 | **iOS 原生标签栏** | `native_tab_bar.dart` 通过 `MethodChannel('venera/native_tab_bar/$viewId')` 回传索引；高度 `_kBottomBarHeight + bottomInset`；`UiKitView` 的 key 由标签拼接 | 用 Flutter 重绘 iOS 底栏（会丢掉真 Liquid Glass）；改 key 导致平台视图重建闪烁 | 只在原生侧换 SF 符号与外观；高度改为原生回报值时保留回退 64 |
| 9 | **章节网格布局** | `chapter_card_layout_test.dart`：320 / 390 / 430 宽、多种 `textScale`；`ChapterCardLayout.coverColumns` 在 296 / 366 / 406 / 528 宽时都为 4（`max(4, floor(w / 110))`）；`coverExtent / textExtent`；`crossAxisSpacing 8 / mainAxisSpacing 14`；日期在标题下、点赞在日期下；缺失数据不显示 `0` | 改章节卡 padding、字号、行数导致 `coverExtent` 不够而溢出；改列数公式；把元信息改成同一行 | 只改颜色、圆角、字重；如需改字号，同步调整 `coverExtent / textExtent` 并在 1.3 / 2.0 倍下验证 |
| 10 | **收藏页交互** | `favorites_page_layout_test.dart`：tooltip `'Hide folder list' / 'Show folder list' / 'Folders' / 'Expand'`；窄屏抽屉出现 `CloseButton`；面包屑是 `TextButton`；移动文件夹对话框用 `ListTile('Top level')`；关闭后无残留遮罩；`ValueKey('favorite_folder_list')` | 把窄屏抽屉改成推入导航栈（`CloseButton` 消失）；把面包屑换成自绘；去掉 tooltip；移动对话框换成非 `ListTile` | 改导航模式前先改测试，或只做视觉；tooltip 与 key 保留 |
| 11 | **评论 golden（像素级）** | `comments_ui_golden_test`、`comments_footer_golden_test`、`comments_rich_golden_test` 共 8 张基准图（`test/goldens/comments/{chapter_sort,thread}_{light,dark}_{100,200}.png`），390 宽、1.0 / 2.0 倍字号；它们用自己的 `ThemeData(brightness, platform: iOS)`，不经过 `getTheme()`；还断言 `CheckedPopupMenuItem`、`Icons.arrow_drop_down`、`Icons.thumb_up_outlined`、tooltip `浏览量 1197000 / 本章获赞 19537`、无 `SelectableText`、只有一个 `Scrollable` | 任何对 `comment_presentation.dart`、`comment_sort_selector.dart`、`comment_context_stats.dart`、`rich_comment_content.dart`，以及它们用到的共享组件（`Button`、`ts`、`AnimatedImage`、`message`）的视觉改动；把排序菜单从 `PopupMenuButton` 改成 `MenuAnchor` | 评论组件放到最后一波；改前先记录基准，改后用 `--update-goldens` 重生成并人工审图；注意因为不走 `getTheme()`，波次 0 的主题改动不会影响它们，但组件内的字面量改动会 |
| 12 | **阅读器源码字符串检查（在 CI 中）** | `reader_customizations_test.dart:49-81` 读取 `scaffold.dart` 源码文本，要求包含 `favoriteComicFromReader / addImageFavorite / pickChaptersAndDownload / downloadFromReader / buildTranslationControls / openChapterDrawer / toggleReadingOrientation / toggleAutoPageTurning / showPageJumpDialog` 和 `effectiveSetting('showReadingProgressPercent')`；`continuous_mode.dart` 含 `effectiveSetting('changeChapterOffset')`；`appdata.dart` 含 `'changeChapterOffset': 160` | 重构外壳时把这些方法拆到新文件或改名（测试按文本匹配，即使逻辑没变也会失败） | 新的外壳组件放新文件，但这些方法名和调用必须留在 `scaffold.dart` |
| 13 | **阅读器按钮类型与手势** | `reader_night_mode_button_test` / `reader_auto_page_turning_button_test`：`find.byType(IconButton)` 点击与长按、`MenuItemButton`、`Slider`、320×568 小屏；`gesture.dart` 的 30% 分区、200ms 双击、250ms 长按、20px 阈值；`reader_back_swipe_test`、`ios_back_swipe_zoomed_image_test`、`back_gesture_*` | 把夜间模式、自动翻页按钮改成自绘 `GestureDetector`；在阅读区上方加全宽透明层（吞手势）；浮动胶囊离边缘太近，与 iOS 返回手势或系统 Home 条冲突 | 玻璃按钮内部仍用 `IconButton`（改 `style` 即可）；浮层只覆盖自身区域；底部胶囊离底 ≥ 8 + 安全区，左右 ≥ 16，避开左缘返回手势区 |
| 14 | **首页 Hero 与编辑** | `home_comic_hero_test`（在 CI 中）：`SimpleComicTile` 数量等于历史数、每个 tile 内有 `Hero` 与 `RawImage`，tag 为 `"cover$heroID"`；`home_edit_back_gesture_test`：tooltip `'Edit Home'`、文案 `'Done'`，返回手势退出编辑 | 首页改用新封面组件而不是 `SimpleComicTile`；去掉 `Hero`；把编辑键移进导航栏菜单（tooltip 消失） | 保留 `SimpleComicTile` 类与 Hero tag 格式；编辑入口移动时保留 `tooltip: 'Edit Home'.tl` |
| 15 | **长按菜单形态** | `context_menu_test.dart`：900×700 下是桌面菜单（出现 `SubmenuButton`），390×844 下必须出现 `BottomSheet`，且有 `FilledButton('Read now')` | 手机端改成 iOS 上下文菜单（`CupertinoContextMenu`），测试失败 | 若要做 iOS 上下文菜单，限定在真 iOS 平台分支，测试环境（默认 android 平台）保留 sheet；或同步改测试 |
| 16 | **弹出页底部留白** | `pop_up_scaffold_bottom_inset_test`：400 宽时底部留白 ≥ 48；900 宽时 0 < 留白 < 48；滚动后头部背景不透明（`alpha == 1`） | 把 `PopUpWidgetScaffold` 头部改成半透明材质（违反 `alpha == 1`）；改底部 padding 计算 | 头部材质化前先确认这个断言的初衷（防内容透出），可以只在 iOS 26+ 上材质化，或同步改测试 |
| 17 | **其他文案 / tooltip 依赖** | `tasks_page_test`（CI）：`'Current (1)'`、`'Clear History'` tooltip、320 宽无溢出、`ExpansionTile`；`library_empty_state_test`：tooltip `'Search'`；`local_library_ui_test`：tooltip `'Sort'`、`SliverGridComics`；`llm_provider_editor_layout_test`（CI）：`Icons.add`、tooltip `'Back'`、360×640 | 把图标按钮换成无 tooltip 的自绘件；把 `ExpansionTile` 换成自绘折叠 | 所有图标按钮保留现有 tooltip 字符串（同时也是 VoiceOver 标签） |

额外提醒：
- `git status` 显示 `lib/components/button.dart` 与 `lib/components/select.dart` 已有未提交修改（不是本次审计产生的，本次只新增了 `REDESIGN_AUDIT.md`）。上表对这两个文件的参数以当前工作区为准，开工前请确认这些修改是否要保留。
- `ui_style == 'glass'` 是用户设置项（`navigation_bar.dart:321, 892`，`reader/scaffold.dart:383-384, 1092-1093`）。去掉分叉时需要处理设置页里对应的选项与已保存值的迁移，否则老用户的设置会悬空。
- 主色改为 iOS 系统色时，`app_slider_theme_test` 断言 `seed == Colors.red` 时滑块偏红、否则偏绿。只要 `getTheme` 仍按传入种子色着色就不受影响。
红、否则偏绿。只要 `getTheme` 仍按传入种子色着色就不受影响。
