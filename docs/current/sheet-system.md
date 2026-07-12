# Sheet System 当前实现

本文记录当前已经落地的 sheet 骨架用法。它面向后续维护者：新增或调整任务 sheet 时，先按这里判断入口和容器，避免再出现第二套顶部按钮、背景或导航栏样式。

## 心智模型

Moodments 的 sheet 分两层治理：

```text
sheet 宿主
  -> AppSheetScaffold：背景、color scheme、tint、NavigationStack 宿主
  -> 顶部动作槽
      -> appSheetChrome：适合系统导航栏的关闭/完成/编辑等动作
      -> AppSheetHeaderBar：适合页内自定义头部的取消/保存等动作
  -> 内容骨架
      -> TaskPageScrollView / TaskResponsiveContent / TaskSurfaceSection
      -> feature 自己的 List、LazyVGrid、输入面板或阅读内容
```

`AppSheetScaffold` 管 sheet 的外壳，不直接决定页面内容怎么排；`TaskContainerStyle.swift` 管任务内容列、panel、row 和滚动内容。两者配合，但职责不同。

## 当前入口

| 场景 | 当前入口 | 顶部动作 |
| --- | --- | --- |
| Moment 编辑页 | `MomentEditorView` -> `AppSheetScaffold(hidesSystemNavigationBar: true)` | 页内 `MomentEditorHeaderBar` -> `AppSheetHeaderBar` |
| Moment 预览页 | `MomentPreviewView` -> `AppSheetScaffold` | `appSheetChrome`：关闭 / 编辑 |
| 设置根页 | `SettingsSheetView` -> `AppSheetScaffold` | `appSheetRootNavigationChrome`，无显式关闭按钮 |
| 设置详情页 | 设置栈 push 子页 | `appSheetDetailNavigationChrome`，保留系统返回 |
| 筛选 half-sheet | `FilterPanelView` -> `AppSheetScaffold` | `appSheetChrome`：清除全部 / 完成 |
| 标签创建/重命名 | `TagCreateSheetView` -> `AppSheetScaffold(hidesSystemNavigationBar: true)` | 页内 `AppSheetHeaderBar`：取消 / 保存 |
| Paywall | `ProPaywallView` -> `AppSheetScaffold(style: .commercial)` | `appSheetChrome`：关闭 |

## 维护规则

- 新增根级任务 sheet 时，默认从 `AppSheetScaffold` 开始，不在 feature 内单独写 `.presentationBackground(theme.sheetBackground)`。
- 适合系统导航栏的动作使用 `appSheetChrome` 和 `AppSheetAction`；不要直接在 toolbar 里写裸的关闭、完成或编辑按钮。
- 需要和页面内容共用自定义垂直骨架的 sheet，使用页内 `AppSheetHeaderBar`；当前例子是编辑页和标签创建页。
- 顶部动作按钮统一由 `AppSheetActionButton` 渲染；禁用、强调、危险色和 accessibility identifier/hint 都通过 `AppSheetAction` 表达。
- 设置详情页保留系统 push/返回语义，只挂 `appSheetDetailNavigationChrome`；不要为每个详情页自绘返回按钮。
- `.themedTaskContainer` 只保留为内容层/任务容器兼容入口，不是新增 sheet chrome 的入口。
- 首页、时间轴气泡、日期/时间 popover、标签选择 popover 不属于任务 sheet system，不套 `AppSheetScaffold`。

## 验证入口

当前 sheet system 的最小回归面优先跑定向测试，避免每次 UI 调整都全量跑慢流程：

```bash
./scripts/test.sh --only MoodmentsUITests/EditorSheetPresentationUITests/testTapFABPresentsEditorWithMoodRowAndSaveButton
./scripts/test.sh --only MoodmentsUITests/DeleteRestorePurgeUITests/testPreviewEditButtonPresentsNestedEditor
./scripts/test.sh --only MoodmentsUITests/EditorSheetPresentationUITests/testSettingsRootHasNoExplicitCloseAndChildPageKeepsBackButton
./scripts/test.sh --only MoodmentsUITests/QuotaBlockUITests/testEleventhMomentBlocked
./scripts/test.sh --only MoodmentsUITests/TagManageUITests/testCreateTagFromTagManageAddsRow
./scripts/test.sh --only MoodmentsUITests/TitleCollapseFilterUITests/testFilterSheetHidesTagCreateEntryAndExistingTagStillFilters
./scripts/test.sh --only MoodmentsUITests/TitleCollapseFilterUITests/testFilterClearAllRemovesSelectedConditions
```

提交前仍需按改动风险补 `./scripts/build.sh`、`./scripts/lint.sh` 或更窄的相关测试；不能只看 diff 判断完成。
