# SwiftUI 当前实现真相

本文记录 SwiftUI 版 HeatMoment 当前已经实现的界面结构、运行路径和已知偏离。这里的事实源是 `Sources/HeatMoment/` 与 `Tests/`，原 Flutter 项目只作为产品语义理解来源，不作为 SwiftUI 当前实现事实。

## 整体模型

当前 App 是单根首页结构：

```text
HeatMomentApp
  -> app fullScreenCover: privacy lock / pending local restore
  -> RootView
      -> TimelineHomeView
          -> TimelineHomeChromeView
          -> HomeContextPanel(YearHeatmapView)
          -> TimelineViewportView
          -> TimelineContextMarkerBar
          -> TimelineFilterSheetPresenter(FilterPanelView)
          -> FAB
      -> rootSheet: preview / editor / settings / paywall
      -> app readiness: launch restore result / canonical prepare / default library seed
```

`RootView` 当前是 App shell：只治理 root scene、根级任务 sheet 呈现策略和进入交互前的 app readiness；HeatMoment 首页由 `TimelineHomeView` 提供。隐私锁和 pending local restore 属于 `HeatMomentApp` 的 App composition full-screen policy；图片查看器不走全局 Router，而由 `MomentPreviewView` 局部 `.fullScreenCover(item:)` 就近呈现，避免保留无写入方的第二条全局路径。

`TimelineModel` 在 `RootView` 创建并注入首页与热力图，承载 `activeFilter`、`heatmapFocusDate` 和 `heatmapAnchorGranularity`。这让“看哪些记录”和“定位到哪里”在代码层保持双状态源，并能表达日/月两种时间 anchor 粒度。

## 首页与时间轴

`TimelineHomeView` 负责首页场景壳层：主画布背景、列表、顶部上下文槽位、底部 FAB 和创建额度闸门。顶部入口已拆到 `TimelineHomeChromeView`；热力图插槽由 `HomeContextPanel` 包住；筛选 half-sheet 的 `.sheet` 修饰符集中在 `TimelineFilterSheetPresenter`，仍由首页局部 `isFilterPresented` 驱动，不进入 `AppRouter`。

`TimelineViewportView` 负责时间轴 viewport、标题折叠、筛选谓词、定位滚动和删除副作用；它不持有热力图展开、筛选 sheet 展开或设置 sheet 呈现状态。

当前时间轴使用 SwiftUI `ScrollViewReader + List`：`List` 只作为成熟滚动和行级 swipe action 宿主，不作为时间轴轨道坐标来源。每条 `TimelineRowView` 由三部分组成：

```text
TimelineDateColumn
  -> TimelineMoodAnchorColumn(MoodNodeView)
  -> BubbleCardView
```

`TimelineSceneMetrics` 是首页时间轴视觉骨架入口，由 `TimelineHomeView` 按当前 viewport 宽度和 `TimelineSceneStyle.standard` 计算一次，再传给 `TimelineViewportView`。它拆成 `TimelineSceneLayout` 和 `TimelineSceneStyle` 两层：layout 只表达日期列、轨道、节点外径、气泡尾巴、标题、顶部 chrome 和 FAB 直径/避让等坐标与呼吸节奏；style 只表达字体、节点内圆比例与透明度、气泡内部形状/内容节奏、图片区、tag chip、顶部图标和 FAB 图标/阴影等视觉参数，不反推时间轴锚点。顶部 chrome 图标使用正负形中性系统：日历入口是透明内芯、顶部实心帽和粗外框组成的小型日期 glyph，顶部帽约占图标高度三成、日期数字约占图标高度一半；设置入口是粗描边六边形 + 中心实心点，两者共用 `neutralIconStroke` 并在亮/暗模式下反转，不跟随主色。`TimelineResponsiveScale` 以 390pt 宽 iPhone 为基准，对窄屏小幅收紧、宽屏小幅放大，并做半点取整，避免不同手机尺寸上视觉对象漂移或撑爆容器。

`TimelineGeometry` 是首页时间轴阅读单元内部坐标系统的单一来源：`listHorizontalInset` 定义整条阅读单元的行内缩进，`dateColumnWidth` / `interColumnSpacing` / `nodeColumnWidth` 定义日期列、节点列和气泡列的横向关系，`readingUnitOriginX` / `nodeCenterXInReadingUnit` / `nodeCenterXInViewport` / `railCenterXInViewport` 定义节点中心与视口轨道的 x 绑定，`bubbleLeadingXInReadingUnit` 定义气泡卡片相对阅读单元的起点，`nodeDiameter` 定义心情节点外径，`nodeCenterY` / `bubbleTailCenterY` 定义心情节点和气泡尾巴在单条 Moment 容器内的纵向锚定关系，`railWidth` 定义轨道线宽，`bubbleTailSize` / `bubbleTailHorizontalOffset` 定义气泡尾巴自身几何。`TimelineViewportLayout` 定义首页首屏场景槽位：展开标题槽位底部、展开标题自身顶部 padding、标题到轨道顶点的呼吸间隔、轨道顶点到第一条 Moment 容器顶部的呼吸间隔和轨道底部超出长度；它同时派生 `expandedTitleContentSlotHeight`，由标题行真实消费，避免轨道计算和 `List` 内容起点脱节。`TimelineHomeLayout` 定义首页固定 chrome 与 FAB 的场景避让，包括顶部 chrome padding、FAB 直径、FAB 吸底距离和底部操作 clearance；FAB clearance 由时间轴 List 尾部 spacer 消费，不再通过首页底部 `safeAreaInset` 缩短时间轴 viewport，因此用户上滑到尾部时仍能看到时间轴铺到屏幕底部。`TimelineViewportMetrics` 消费 viewport layout、viewport 尺寸和滚动 offset，生成 `TimelineRailSceneBounds`、`restingFirstReadingUnitTopY` 和 `restingFirstNodeCenterY`。场景轨道的顶点和底端由 `TimelineRailSceneLayer` 消费 `TimelineViewportMetrics` 绘制，不再反向依赖 `List` 行的 `PreferenceKey` 上报；`List` 是惰性布局，不能作为整条轨道是否存在的真相源。后续如果要移动时间轴横向位置、调整日期列、节点列、节点在 Moment 容器内的位置或气泡尾巴关系，优先改 `TimelineGeometry`；如果要调整轨道首屏 y、标题到轨道顶点间隔、轨道顶点到第一条 Moment 容器顶部间隔或底部超出，优先改 `TimelineViewportLayout`；如果要调整顶部 chrome 或 FAB 避让，优先改 `TimelineHomeLayout`；如果要调整字体、节点内圆、气泡内部样式、顶部图标或 FAB 图标/阴影，优先改 `TimelineSceneStyle`；如果要调整上滑/下拉相位，优先改 `TimelineViewportMetrics`。

`TimelineViewportView` 使用 `ScrollViewReader + List` 承载成熟滚动、定位和行级 swipe action。`List` 自身设置 `defaultMinListRowHeight = 0` 和 `listRowSpacing(0)`，让标题槽和首条 Moment 前 lead-in 由 `TimelineViewportLayout` / `TimelineGeometry` 控制，不被 SwiftUI 默认 44pt 行高覆盖；尾部 spacer 使用 `TimelineViewportLayout.bottomTailClearance(protecting:)`，由轨道视觉 overshoot 与 `TimelineHomeLayout.bottomActionClearance` 共同决定。连续轨道由 `TimelineRailSceneLayer` 作为 viewport 场景层绘制，不属于任何 `List` row、阅读单元或气泡；日期列、心情节点和气泡是行前景阅读单元。`TimelineRailVisibility` 决定是否渲染场景轨道：只有存在可见阅读单元时才画轨道；筛选后 0 条命中时只显示空态文案，不渲染轨道或 lead-in / bottom tail，避免出现没有日期、节点、气泡归属的孤立竖线。轨道场景层不参与 `List` 行级 `.swipeActions`，因此左滑删除时系统移动日期、节点和气泡这个阅读单元，轨道不会被 row swipe 容器移动、裁剪或切断。滚动监听在 iOS 18+ 使用 SwiftUI `onScrollGeometryChange`，iOS 17 使用挂在 `List` 自身的零尺寸 `TimelineScrollOffsetReader` 读取承载 `UIScrollView`；这条读取链路输出 viewport 滚动相位，用于标题折叠和轨道 y 相位，不反推轨道 x 坐标或节点位置。

`TimelineRowView` 只承载日期列、心情节点和气泡组成的阅读单元。记录的日期列由当前可见列表中的相邻记录决定展示模式：列表首条或跨天首条显示完整日期块（第一行日 + 月，第二行时间），同一天后续记录只显示发生时间并用 `TimelineGeometry.nodeCenteredLabelMinHeight` 将单独时间的视觉重心对齐到节点中心，让一天内多条 Moment 在左侧时间信息上连续而不重复日期。左滑删除由 SwiftUI `List` 行的 `.swipeActions(edge: .trailing, allowsFullSwipe: true)` 提供，所以轻扫露出删除按钮、继续左滑按钮拉长并触发删除都交给系统成熟组件；连续时间轴轨道不参与横向位移。节点中心、气泡尾巴中心和尾巴尺寸/偏移由 `TimelineGeometry` 约束，再传入 `BubbleCardView`；当前代码结构已经把轨道、日期列、节点列和气泡列放到同一坐标系统中，并提供尾巴指向时间线的实现路径。

`BubbleCardView` 是首页 Moment 气泡的展示合同：标题、正文和图片按 `MomentCardContentKind` 覆盖标题-only、正文-only、标题+正文、文字+图片、纯图片等状态；气泡宽度跟随时间轴内容列，不由标题长度、图片数量或原图比例反向撑开。气泡圆角、内边距、内容间距、尾巴、图片区和 tag chip 由 `TimelineBubbleStyle` 注入，后续皮肤替换气泡形状或图片区节奏不需要改行级坐标。图片区尺寸由 `MomentCardLayout` 转发 `TimelineImageGalleryStyle.standard` 固定：滚动模式使用固定缩略图高度，轮播模式使用固定轮播高度；图片走 `ThumbnailStripView` 按需加载缩略图。图片裁切使用 `scaledToFill + clipShape`，所以不同原图比例只影响缩略图裁切内容，不改变时间轴坐标。首页气泡图片区保持 hit testing，图片上的横向手势优先用于缩略图滚动或轮播切换；非图片区仍由 `List` 行级 `.swipeActions` 承担删除。

记录点击气泡后写 `router.rootSheet = .preview(moment.id)`，VoiceOver 默认动作同样打开预览阅读卡片。左滑阅读单元使用系统 `.swipeActions` 软删除到垃圾箱；轻扫会露出“删除”按钮，继续滑动可触发系统 full swipe 删除；VoiceOver 删除替代路径挂在行级可访问元素上。

根级 sheet 或筛选 sheet 展开时，`TimelineHomeView` 保留主页时间轴层级，不卸载 `TimelineViewportView`，以维持主场景返回态和滚动连续性；同时通过 `suppressAccessibility` 把后台时间轴行从可访问树中压低，避免临时任务上下文中误操作背景内容。垃圾箱相关 UI 测试只命中 `trashRow-*`，不把后台同名 Moment 行当作垃圾箱行。

## 热力图与定位

`YearHeatmapView` 由 `TimelineHomeView` 的首页局部 `isHeatmapPresented` 状态驱动，插入顶部 `safeAreaInset` 中的 `topBar` 下方。它不是 sheet、不是 full screen cover，也不进 `AppRouter`；展开后保持全宽首页上下文区，使用 material + `homeContextSurfaceTint` 浮在唯一的 `HomeSceneBackgroundView` 之上。热力图自身不再实例化首页背景，避免 `customImage` 在热力图区域重新裁切成第二套背景。

热力图当前行为：

- 年度聚合会读取当前 `activeFilter`，用于展示当前筛选口径下的年度分布。
- 打开年度网格后，网格自身横向滚动会优先把已选 anchor 所在月份带入视野；没有已选 anchor 且正在查看当前年时，把当前月份带入视野。这只改变热力图内部滚动位置，不写入时间轴定位状态。该网格组件同时服务首页热力图和心情统计页；统计页仍是纯展示，不写时间轴定位状态。
- 点日期写入日粒度 anchor；点有记录的月份标签写入月粒度 anchor。两者都只更新 `timelineModel.heatmapFocusDate` 和 `timelineModel.heatmapAnchorGranularity`；当前热力图口径下没有记录的月份只显示同尺寸文本，不提供月份定位按钮。
- `HeatmapGridView` 在月粒度选中时用当前主色低透明蒙层覆盖对应月份列区，蒙层位于日期格上方且不拦截点击；日粒度选中时仍用日期格描边。
- `TimelineViewportView` 监听包含 anchor 日期、粒度和目标行的派生滚动请求后，在当前可见 `entries` 中计算滚动目标；日 anchor 只命中同一天记录，月 anchor 只命中同一月记录，不会退到更早日期或更早月份。
- 换年会清空 `heatmapFocusDate`。
- 再点同一天或同一月会取消定位高亮，不主动改回滚动位置。

这条路径保持“定位不等于筛选”：热力图选择不会改写 `activeFilter`，筛选变化也不会被当作时间锚点。筛选变化后，如果当前可见集内没有该日或该月记录，定位标记仍可保留，但滚动目标为 `nil`，不会偷偷放宽筛选。

## 筛选与上下文标记

筛选入口只在标题折叠后出现。当前实现是 `TimelineHomeView` 局部 `isFilterPresented` 驱动的 `FilterPanelView` sheet，属于首页就地筛选层，不进入 `AppRouter.rootSheet`，也不进入任务卡片栈：

```text
TimelineHomeView.timelineFilterSheet
  -> .sheet(isPresented:)
      -> FilterPanelView(activeFilter:)
```

`FilterPanelView` 使用 `AppSheetScaffold + appSheetChrome + ScrollView + LazyVGrid`；半屏 / 大屏 detent 仍由 `TimelineFilterSheetPresenter` 管理。标签支持多选 AND，心情单选，显式提供“全部心情”；点选即时写入 `activeFilter`；“完成”只负责收起 sheet，选择条件不会自动关闭 sheet；“清除全部”会一次性移除心情和标签筛选。筛选 sheet 只选择已有标签，不提供新增、重命名、删除入口，也不会打开 `TagCreateSheetView` 第二层 sheet。

`TimelineContextMarkerBar` 同时显示筛选标记和时间定位标记。移除筛选标记改变 `activeFilter`，移除时间标记清空 `heatmapFocusDate` 与 `heatmapAnchorGranularity`。日 anchor 显示为 `M月d日`，月 anchor 显示为 `M月`。

## 当前持久化与同步状态

当前生产主 UI、用户写入、完整备份包、本机安全点和 Markdown/PDF 导出路径的唯一读写权威是 GRDB canonical store。启动、时间轴、编辑、预览、标签、垃圾箱、统计/热力图、图片读取、备份、Markdown/PDF 导出和 UI 测试种子都走 canonical 数据源。

`Sources/HeatMoment/Persistence/Canonical/` 是 GRDB canonical local core。它当前包含 SQLite migration、library metadata、moment/tag records、稳定排序的 moment-tag link、asset/link metadata、content-addressed `FileAssetStore`、content-hash `asset_pin_record` lease、canonical recovery point catalog、canonical recovery coordinator、canonical boot restore gate、canonical migration safety gate、asset reachability audit、GC dry-run plan、DB orphan asset record finalizer、orphan blob cleanup、tombstone、mutation log、`CanonicalLibraryRepository` 的事务边界，以及 `CanonicalLibraryRuntime` 装配类型。`Services/BackupPackage/` 是完整备份包能力边界，负责 `.heatmomentbackup` 单文件容器、manifest、payload 校验、导出和导入 staging。`HeatMomentApp` 普通启动先调用 `CanonicalBootRestoreGate.performProductionPendingRestoreIfNeeded()`，在打开 `CanonicalLibraryRuntime` 前消费已 armed 的 pending restore；随后创建 `CanonicalLibraryRuntime`、`CanonicalLibraryService`、`CanonicalRecoveryCoordinator`、`CanonicalBackupPackageService` 等服务并注入。`RootView` 在展示主界面前调用 `CanonicalLibraryService.prepareIfNeeded()`，该准备步骤只标记 canonical facade 可用并刷新 `changeToken`。

`CanonicalLibraryRepository` 已补齐 M1 repository parity 并通过 `CanonicalLibraryService` 接到主 UI。`CanonicalMomentRecord` 会按 `moment_asset_link.sort_index` 返回稳定 `imageIDs`；`createMoment` 可在同一业务写入中接收原图 bytes，先通过共享 `CanonicalAssetOperationGate` 写入 content-addressed blob，再在 SQLite 事务里写 `moment_record`、`moment_tag_link`、`asset_record`、`moment_asset_link` 和 `mutation_log`，DB 事务失败时会清理本次新写入的 blob。`updateMoment(imageDatas: nil)` 保留原有图片关系；传入非 nil 图片数组时会替换图片链接和 asset metadata，并 finalize 无 link 且 `pin_count == 0` 的旧 `asset_record`。图片 bytes 读取通过 `imageData(imageID:)` 和 `orderedImageData(momentID:)` 从 `FileAssetStore` 取回；缺失 Moment、终态删除 Moment 或不可读图片 ID 会抛出 repository error，不做空结果兜底。当前 repository 还提供预览/编辑所需的 `fetchMoment`、`editingPayload`、标签名回填、`findTag(named:)`、带心情和标签 AND 条件的 `fetchPage(filter:)`、`availableYears`、`moodByDay`、`moodCounts`、`totalMomentCount` 和 `totalTagCount`。定向测试 `CanonicalRepositoryParityTests` 覆盖图片顺序、编辑 payload、nil 图片更新保留、非 nil 图片更新替换、缺失 ID 快速失败、终态删除直读拦截、带图片写入 DB 回滚后的 blob 清理、筛选分页、每日心情、年度统计、年份列表和标签查找。

canonical recovery catalog/snapshot/coordinator/restore service/migration safety gate 已接入写入触发器、完整备份导入前安全点和普通启动路径。`asset_pin_record` 按 `content_hash` 建模，使用 `owner_kind + owner_id` 表达 recovery point、restore staging、export job、sync 等 owner 的 lease；`expires_at == nil` 表示必须显式 release，过期 lease 不再保护 blob。`CanonicalAssetPinStore` 当前提供 upsert 式 pin、按 content hash release、按 owner 批量 release 和按 owner kind 批量 release，拒绝 invalid content hash、empty owner 和 invalid expiration。v4 schema 新增 `recovery_point_record` 和 `recovery_point_asset_record`；v5 schema 将恢复点摘要从标签库数量切到已用标签数量，使用 `used_tag_count`，并切断旧 recovery point catalog/pin，下一次 `CanonicalLibraryRuntime(descriptor:)` 初始化会按 catalog 对账清理旧 `RecoveryPoints` 目录残留。`CanonicalRecoveryPointStore` 在单个 GRDB 写事务内写入恢复点 catalog、SQLite 快照相对路径/字节数/hash、记录/已用标签/照片计数、asset manifest，并为 manifest 中的 content hash 写入 `owner_kind = recoveryPoint` pin；默认创建第 4 个恢复点后按 `createdAt DESC, id DESC` 保留 3 个，淘汰最旧恢复点并释放对应 recoveryPoint pin。`CanonicalRecoveryPointSnapshotService` 使用 `CanonicalStore.backup(to:)` 包装 GRDB online backup 创建真实 SQLite snapshot，并在 `CanonicalAssetOperationGate` 内完成“snapshot -> manifest -> blob validate -> catalog pin”。`CanonicalRecoveryCoordinator` 继续作为内部恢复点应用服务边界，兼容性要求 schema version、app version 和 source library 与当前库一致；完整备份包导入不复用这条 source library 限制，`sourceLibraryID` 只作为 manifest 元数据和预览审计字段。`CanonicalRestoreExecutor` 支持两种 staging 来源：本机恢复点 snapshot，以及已校验完整备份包里的 imported snapshot；两者最终都写入 pending context、armed marker，并在下次冷启动由 `CanonicalBootRestoreGate` 替换 SQLite payload。restore safety 的 catalog 和 asset manifest 会写入 pending context；boot replace 时 `CanonicalRestoreExecutor` 会先在 incoming snapshot 内删除 snapshot 文件已缺失的旧 catalog 行，再注入 restore safety，并按最多 3 个恢复点执行 retention，因此还原完成后仍保留还原前安全点，且不会展示已被文件系统淘汰的幽灵恢复点。`CanonicalMigrationSafetyGate` 是内部 cutover/migration 安全闸门：调用方必须先创建 `.schemaMigration` 恢复点并立即校验，创建失败、校验失败、校验到不同恢复点或恢复点不可用都会抛错中止。

`CanonicalAssetReachabilityService` 当前只做维护面审计和受保护 cleanup：从 `asset_record`、`moment_asset_link`、`asset_pin_record` 和 asset store 文件系统聚合 `content_hash`，报告无 link 的 asset record、active/expired pin、invalid pin hash / invalid pin expiration、negative `pin_count`、DB 引用缺失 blob、active pin 保护对象缺失 blob、corrupt blob、invalid hash/path，以及 DB 无引用且无 active pin 保护的 orphan blob。`planGarbageCollection()` 是 dry-run：列出可 finalize 的 unlinked + unpinned `asset_record`、当前 orphan blob，以及 finalize 后才会变成可删且没有 active pin 的 blob hash。`finalizeUnlinkedAssetRecords()` 在 `CanonicalAssetOperationGate` 内执行，并在 DB write transaction 中重新确认整批 planned record 仍然 no-link 且 `pin_count == 0` 后只删除 `asset_record`；若整批条件不一致则抛出 race 错误且不提交部分删除。它不删除 blob，也不会因为 content-hash pin 阻止 DB orphan record finalization。`cleanupOrphanBlobs()` 只在没有 blocking issue 时删除 DB 无引用且无 active pin 保护的 orphan blob，不参与业务写入事务。完整备份包导出在 `CanonicalAssetOperationGate` 内复制 blob，并使用 `owner_kind = exportJob` pin 保护导出期间的 content hash；完整备份包导入把包内 blob 写入当前 `FileAssetStore` 后，复用 `owner_kind = restoreStaging` pin 保护下次启动前的 pending restore 资产。现有 `asset_record.pin_count` 只能作为 record-level 保护信号，不是最终 GC 依据。M-architecture-final 后，restore executor 的 pending restore / boot restore 类型合同移入 `CanonicalRestoreTypes`；恢复点 snapshot service 的无 gate helper 继续保持文件内私有，避免扩大可绕过 `operationGate` 的调用面。定向测试覆盖 schema migration、Moment 生命周期、`purgePending`、标签 create-or-reuse、额度、rename/delete、删除标签时受影响 Moment 的 revision/mutation、tag tombstone、缺失引用回滚、稳定排序约束、重名冲突回滚、runtime 落盘建库、content-addressed 原图写入/读回/去重、recovery point catalog / asset manifest / recoveryPoint pin lifecycle、真实 SQLite snapshot 创建/校验/淘汰目录清理、内部 canonical recovery coordinator 的创建/节流/并发/安全点/prepare restore 组合语义、内部 canonical restore executor stage/arm/boot replace/rollback/rollback critical failure 回归/restoreStaging pin 清理、完整备份包导出/预览/篡改拒绝/跨 runtime 导入 staging、内部 boot restore gate 在 runtime 打开前消费 pending restore、内部 migration safety gate 在 destructive migration / cutover 前创建并校验 `.schemaMigration` 恢复点，以及 asset reachability audit / content-hash pin / pin-aware GC dry-run / DB orphan record finalizer / orphan blob cleanup 的安全边界。

当前 UI 用户写入入口通过 `LocalLibraryMutationService` 进入应用服务边界：创建/编辑/软删除/恢复/彻底删除时刻以及创建或复用/重命名/删除标签都调用 `CanonicalLibraryRepository`，成功后通过 `CanonicalLibraryService.noteCanonicalChange()` 驱动 SwiftUI 重新加载，并处理同步状态标记和缩略图失效。普通写入成功后通过 `CanonicalRecoveryWriteRecorder` 异步请求 `CanonicalRecoveryCoordinator.createStableChangesRecoveryPointIfNeeded()`，高风险写入前同步创建 mutation safety 恢复点，安全点创建失败会抛出 `LocalLibraryMutationError.mutationSafetyPointFailed` 并中止后续恢复、彻底删除或标签删除。跨 actor 传递使用 `MomentSnapshot`、`MomentEditingPayload`、`CanonicalMomentImageData`、`TagSnapshot` 等值类型，不把 GRDB row 引用传出边界。

`Config/HeatMoment.entitlements` 保留 CloudKit 私有库声明，但默认不接入 `Project.yml` 的 App target，避免 Personal Team 真机开发签名被 iCloud entitlement 阻断；未来恢复 iCloud 同步时再启用该 entitlements 文件并使用支持 iCloud 的付费 Team。当前同步状态由 `SyncStatusService` 根据 `FileManager.default.ubiquityIdentityToken` 推导出的 iCloud 能力、网络可达性和最近本地写入时间推导 `offline / syncing / synced`，不读取真实 CloudKit import/export 事件，不表达冲突、重试队列、服务器变更 token 或错误详情；该状态也不表示 canonical 写入已经通过 iCloud 同步。

设置页根页当前提供“备份/还原”入口，push 到 `BackupRestoreView`；该详情页默认表达完整备份能力，消费 `BackupPackageServicing`，生产由 App composition 注入 `CanonicalBackupPackageService`。页面默认只显示摘要卡片、完整备份操作选择和单个主操作按钮；摘要卡片由 `BackupPackageLibrarySummary.currentSnapshot` 与 `lastExportSnapshot` 两个值对象驱动，当前内容和上次导出都按记录数、已用标签数、照片数和时间对称展示，UI 不拼接历史状态。导出备份与导入还原互斥选择，不再作为并列主按钮展示，本机 recovery point、schema version 和来源版本不作为常驻用户概念展示。导出会先在 `BackupPackageExports/Prepared/<packageID>/` 生成临时 `.heatmomentbackup` 完整包，并立即打开系统分享/保存；只有 `UIActivityViewController` 返回 completed 后，service 才把 prepared export 的 counts 与 completed 时间作为上次导出 snapshot 写入历史，并用 `.share-completed` marker 保留本次分享源包一小时，避免 Files / iCloud Drive 在保存收尾时遇到已删除的源文件。用户取消分享或重新进入页面时，未完成的临时包会被清理；已完成的临时包超过保留窗口后由显式清理入口清理。App 不承诺知道用户后续保存路径，不替换或删除外部旧备份。导入使用系统 file importer，先复制文件到 App staging，再校验 magic、manifest length、manifest、payload 相对路径、字节数、SHA-256、尾部数据、SQLite catalog 和 asset manifest；校验通过后直接弹出还原确认 sheet，展示备份时间、内容计数和替换提示，用户确认后才写入资产、创建还原前安全点、stage pending restore 并 arm 下次冷启动替换；导入不会把上次导出 snapshot 改成导入时间或备份包创建时间。用户取消确认或下次进入页面/开始新导入时，未确认的 import staging 会被清理；已 armed 的 pending restore 不在 `BackupPackageImports` 下，不作为临时垃圾清理。

当前用户可见命名与内部符号边界分开维护：`BackupRestoreView`、`SettingsRoute.backupRestore`、`settingsBackupRestoreRow` 和 `BackupRestoreServicing` 仍作为既有 route/capability 标识保留；设置页展示给用户的是“备份/还原”。

当前 Markdown / PDF 导出已切到 canonical source：设置页“导出（Markdown, PDF）”入口进入标题为“导出”的详情页，页面沿用 settings detail navigation chrome、`TaskPageScrollView` 和 `TaskSurfaceSection`；只保留日期、照片开关、格式选择、导出按钮和失败状态，不展示备份恢复相关内部机制说明，也不展示页面内导出结果区或二次分享链接。`ExportView` 只消费 `ExportServicing`，生产由 App composition 注入 `CanonicalExportService`；`CanonicalExportService` 才负责从 canonical repository 组装 `CanonicalExportSnapshotStore` 和 `ExportService`。同一份 `ExportRequest` 表达日期范围、格式和是否包含照片，同一份 `ExportSnapshot` 供 Markdown/PDF 渲染。日期范围按用户选择日期的整日边界查询，开始日期晚于结束日期会被拦截，所选范围没有 active Moment 时导出失败而不是生成空文档；照片开关关闭时两种格式都不读取或写出图片。snapshot 只读取 canonical active Moment，按 `occurredAt` 倒序生成导出输入，标签按 Moment 的 canonical link 顺序输出，图片按 `moment_asset_link.sort_index` 从 `FileAssetStore` 读取原图 bytes。导出路径按职责拆成 `ExportServicing` 能力合同、`ExportService` 编排、`CanonicalExportSnapshotStore` 快照读取、`ExportFileWriter` 临时目录/文件写入、`MarkdownExportRenderer` 文本和相对附件路径渲染、`PDFExportRenderer` 本地分页和图片嵌入；`ExportViewState` 只承载设置页导出轻量状态。`ExportServicing.prepareShareTransaction` 只返回 `ExportShareTransaction`，表达本次待分享的临时文件；分享完成或取消后由 `finishShareTransaction` 结束事务并清理临时副本，不再暴露旧“生成结果”模型。渲染和文件写入在 detached task 内执行，不占用设置页 UI actor；导出中禁用重复点击；坏图片在 PDF 导出中显式失败，不静默跳过，并在导出详情页展示失败状态和重试入口。Markdown 成功后立即用系统分享整个导出目录，避免只分享 `.md` 时丢失相对附件；PDF 成功后立即用系统分享单个 `.pdf` 文件。系统分享完成或取消后，App 清理本次临时副本；系统分享返回错误时保留本次临时副本并展示重试入口；如果 App 在生成后、分享中或清理前被杀死，下次进入导出页会先清理遗留临时副本。当前不支持当前主页筛选、后台导出进度或持久导出任务；Markdown/PDF 导出不写 canonical store，不创建恢复点，不触发同步状态变更。

当前本地文件分层如下：Moment 原图归 content-addressed `FileAssetStore`，SQLite 只保存 asset metadata 和 link 顺序；UI 测试种子直接写 canonical repository；首启默认资料库的 seed 版本记录在 canonical `library_metadata.default_seed_version`。缩略图在 `Caches/thumbnails`，可从 canonical 原图重建，不参与同步；外观自定义背景图在 Application Support 的外观目录，不进入 canonical 资料库或 CloudKit；语言、隐私锁、订阅缓存、外观偏好和“上次导出完整备份摘要 snapshot”使用 `UserDefaults`，该 snapshot 包含导出完成时间和导出包内的记录数、已用标签数、照片数。完整备份包 import staging 位于 canonical Application Support 根目录下的 `BackupPackageImports`，仅承载未确认导入预览，取消确认、进入页面或开始新导入时主动清理；导出准备态临时包位于 `BackupPackageExports/Prepared/`，完成系统分享/保存后或取消/重新进入页面时清理，最终 `.heatmomentbackup` 由系统分享/保存交给用户管理；Markdown / PDF 导出文件分别写在系统临时目录的 `HeatMomentExports/Markdown/` 和 `HeatMomentExports/PDF/` 下，进入导出页和每次新导出都会清理临时目录内旧的 `HeatMoment-*` 导出包，属于用户显式生成的只读分享文件，不参与恢复点或 iCloud 同步。

## 编辑页局部选择

`MomentEditorView` 是任务卡片栈第一层。编辑器使用全局 `AppSheetScaffold` 承载 sheet 宿主，顶部 `取消 / 日期 / 时间 / 保存` 统一进入 `appSheetChrome`：取消和保存使用 `AppSheetActionButton`，日期/时间作为 toolbar principal。`MomentEditorLayoutTokens -> MomentEditorLayoutResolver -> MomentEditorLayoutMetrics` 只管理编辑内容区、日期/时间 principal 间距、顶部到心情/标签行的呼吸间隔、正文区和图片区的垂直呼吸间隔。保存按钮在模型加载前或草稿不可保存时禁用。情绪、标签、日期和时间选择当前由 SwiftUI 代码实现为局部选择：

- 情绪行打开 `MoodPickerView`。
- 标签行打开 `TagPickerView`，只选择已有标签，不提供新增入口。
- 顶栏日期 chip 打开 `DatePickerSheetView`。
- 顶栏时间 chip 打开 `TimePickerSheetView`。
- 这些选择器都由局部 `.popover` 呈现，不进入 `AppRouter`。
- 日期使用系统 `.graphical` `DatePicker`。
- 时间使用系统 `.wheel` `DatePicker`。
- 选择后通过 `OccurredAtComposer` 合成 `occurredAt`，只改变日期或只改变时间。
- 没有额外确认按钮。

这条代码路径使用系统日期/时间控件，未为基础 picker 重做自定义控件。当前测试面覆盖日期和时间 popover 的打开/收起，并用 `OccurredAtComposerTests` 覆盖“只改日期保留时分秒 / 只改时分保留年月日和不可见秒”的合成语义。

## 设置与外观

`SettingsSheetView` 是根级第一层 sheet，使用 `AppSheetScaffold + TaskPageScrollView`，由统一 sheet 宿主提供 `NavigationStack`、背景、色彩模式和 tint。根页不提供显式关闭按钮，依赖系统 sheet 下滑关闭；根页只编排入口和设置栈内导航，具体能力实现留在各 feature / capability。设置入口由 `SettingsNavigationEntry -> SettingsRoute -> settingsDestination(for:)` 统一表达，row 只声明标题、identifier 和目标 route；详情页均在设置栈内 push 并保留系统返回；Pro 横幅使用设置内部局部 `.sheet(item:)` 打开 `ProPaywallView`。

当前设置页信息架构：

```text
Pro 横幅
个人化
  外观主题 -> 详情页
  语言     -> 详情页
数据与安全
  数据与 iCloud -> 行内同步状态，不是账号/登录入口
  备份/还原          -> 详情页
  导出（Markdown, PDF） -> 详情页
  面容解锁      -> 根页开关或不可用状态
管理
  标签管理 -> 详情页
  垃圾箱   -> 详情页
  心情统计 -> 详情页
权益与关于
  关于心绪日记 -> 详情页
```

任务页的响应式骨架收口在 `AppSheetScaffold.swift` 和 `TaskContainerStyle.swift`：

```text
TaskSurfaceMetrics
  -> AppSheetScaffold / appSheetChrome
  -> TaskPageScrollView
      -> TaskSurfaceSection
          -> TaskSurfacePanel
              -> TaskSurfaceRow / feature content
```

`AppSheetScaffold` 只治理 sheet 的宿主 `NavigationStack`、背景和色彩模式；`appSheetChrome` 负责适合系统导航栏的任务页动作槽位，当前用于 `MomentPreviewView` 的「关闭 / 编辑」、`MomentEditorView` 的「取消 / 日期时间 / 保存」、`TagCreateSheetView` 的「取消 / 标题 / 保存」、`ProPaywallView` 的「关闭」和 `FilterPanelView` 的「清除全部 / 完成」。内容区域仍由 `TaskPageScrollView`、`TaskResponsiveContent`、功能视图或商业页自身负责；设置栈内子页保留系统 `NavigationStack` push/返回语义，通过 `AppSheetNavigationChrome` 统一标题与 scroll-edge。

`TaskSurfaceMetrics` 定义任务页内容列的水平边距、最大可读宽度、分组间距、panel 圆角、panel padding 和 row 最小高度。`TaskPageScrollView` 负责 sheet 背景、滚动和底部安全余量，并读取当前 `AppSheetStyle` 决定普通 / 商业 sheet 背景；`TaskResponsiveContent` 只负责内容列居中、最大宽度和页边距，可被统计页等设置栈详情复用；`TaskSurfaceSection` 负责可选标题和 panel 边界；`TaskSurfacePanel` 只表达任务容器面板；`TaskSurfaceRow` 表达设置类行。用于 UI 验证的 section measurement identifier 是 1pt 透明边界标记，不覆盖整块内容，避免抢走按钮命中区域。

这套骨架只用于“系统任务空间”：设置根页、外观详情、编辑器输入面板、预览阅读卡片、筛选 half-sheet、标签创建 sheet，以及统计/标签/垃圾箱的页边距基线。它不用于首页品牌画布、首页热力图上下文 surface、时间轴 Moment 气泡、日期/时间 popover 或标签选择 popover；这些对象各自保留自身语义。当前 Settings 的 Pro 横幅、个人化、数据与安全、管理、权益与关于分组共享同一内容列；Appearance 的模式、颜色、背景、图片分组共享同一内容列；Editor 的文本输入 panel 和添加照片 CTA 共享同一内容列；Preview 的阅读内容、Paywall 购买态内容、Filter 的筛选内容、TagCreate 的输入内容和 MoodStats 的统计卡片也进入统一 sheet/content 骨架。

`TagManageView` 是当前标签新增、重命名、删除的唯一管理入口。右上“+”在打开 `TagCreateSheetView` 前经 `QuotaService` 做标签额度闸门，超额时打开 `ProPaywallView`；`TagCreateSheetView` 在真正创建新标签前再次复核标签额度，避免表单打开后数量变化造成越额写入。`TagCreateSheetView` 使用设置子页上的局部 `.sheet(item:)` 呈现为第二层任务卡片，当前为 `.large` detent 的系统 page sheet；宿主使用 `AppSheetScaffold`，顶部通过 `appSheetChrome` 呈现「取消 / # 标签名称 / 保存」，内容区只保留标签名输入，重命名态复用同一骨架并预填原名。列表行点击进入重命名，左滑使用统一的系统 `.swipeActions(allowsFullSwipe: true)` 展示删除按钮并支持 full swipe。删除成功后调用 `TimelineModel.discardFilterTag` 清理当前筛选中可能残留的标签 id。

`AppearanceThemeView` 已有四组设置：

```text
模式
颜色
背景
图片
```

这些选项通过 `ThemeManager` 即时更新并持久化到 `AppearanceStore`。保存失败和偏好修正提示使用页内文本，不走全局 alert。

当前外观设置的落地边界：

- `DesignSystem` 只保留基础 UI 和基础主题能力：`AppSheetScaffold`、`AppSheetNavigationChrome`、`TaskContainerStyle`、sheet/header action、任务内容列、通用删除 swipe modifier、`ThemeManager`、`AppThemeTokens`、基础色板、排版和外观偏好存储。它不承载 `Moment`、`Mood`、`Tag`、`Timeline`、`Heatmap` 等 HeatMoment 业务组件，也不读取 repository、service 或 canonical 数据。
- `MoodNodeView`、`BubbleCardView`、`HomeSceneBackgroundView`、`FABButtonView`、`TopBarIconButtons` 和 `TimelineSceneStyle` 已归入 `Features/Timeline`；`HeatmapGridView` 归入 `Features/Heatmap`；`MoodStatBarView` 归入 `Features/Stats`；`ThumbnailStripView` 归入 `Features/MomentMedia`；`MoodPalette` 归入 `Features/Mood`。这些是 HeatMoment 业务 UI / 业务色板，不是通用 foundation 合同。
- `ThemeManager` 是运行时基础主题 token 消费入口，并暴露 `tokens: AppThemeTokens` 作为当前模式 + 主色解析后的稳定 token。基础定义层包括 `BrandCanvasPalette`（首页品牌画布）、`MemoryObjectPalette`（记忆对象表面）、`TaskContainerPalette`（sheet/设置/编辑等任务容器）、`AccentPalette`（行动强调主色及其派生前景）和 `FixedIntentColor`（危险、商业固定、图片查看器媒体色）。业务心情色不进入 `AppThemeTokens`。
- 业务 view 不直接新增十六进制色值，P2b 触达范围内的二级文字、弱提示、强调色前景、选中弱填充、禁用强调填充、热力图月份高亮、首页纹理色、自定义背景遮罩、顶部 chrome 叠色、热力图分隔线、预览外框、商业固定色和图片查看器固定媒体色均经基础主题 token 或业务 palette 消费。
- 模式、主色会影响已接入 `ThemeManager` 的背景、文字、气泡、chip、热力图空格、顶栏图标描边、首页背景纹理、行动强调前景和外观页分组缩略卡等。亮色不是暗色反相：首页仍使用轻灰紫画布，任务 sheet 使用 iOS 分组浅色体系，首页气泡和 sheet panel 不互相复用。
- 心情色通过业务侧 `MoodPalette.color(_:mode:)` 解析，只消费当前外观模式，不读取主色；热力图和统计条只通过业务 palette 取得心情色及其轨道派生色。
- 危险色通过 `theme.danger` 解析，不读取主色。
- `ProPaywallView` / `AboutView` 使用固定商业 token，并在本页局部注入 `.light` color scheme：浅色背景、浅色行/面板、固定红和固定商业文字不跟随用户主色或暗/亮模式，也不被设置任务容器的暗色环境污染。Paywall 由 `AppSheetScaffold(style: .commercial)` 承载，购买态内容复用 `TaskPageScrollView` 的统一内容列；月订阅 / 终身买断结构仍按当前 StoreKit 契约展示；双方案视觉样式是否继续改造仍归 Paywall 专项裁决。
- DEBUG / Dev 构建存在本地开发者 Pro 解锁：`SubscriptionDebugOverride` 只在 `#if DEBUG` 编译进包，普通 Xcode Debug 运行时让 `SubscriptionService.currentEntitlementIsPro()` 返回 Pro，并让 `isPro` UI 快照显示为已解锁；它不写入订阅缓存、不伪造 StoreKit 交易，Release 构建不包含该逻辑。单元测试环境、`-uiTest...` UI 测试启动参数、`-disableDebugProUnlock` 启动参数或 `HEATMOMENT_DISABLE_DEBUG_PRO_UNLOCK=1` 环境变量会关闭该 override，以保留免费额度和 StoreKit 回归测试路径。
- `ImageViewerView` 使用固定媒体 token：沉浸黑底、白色 chrome 和黑色 chrome scrim，不跟随主题主色。
- `AppSheetScaffold` 是根级任务 sheet 的 SwiftUI 宿主封装：编辑器、预览和 Paywall 统一由它注入任务背景、color scheme、toolbar color scheme 和 tint。`TaskContainerStyle` 保留内容层封装：`TaskPageScrollView` / `TaskSurfacePanel` 表达响应式宽度与 panel 语义；统计页也使用 `TaskPageScrollView` 和 `sheetPanelBackground`，不再继承首页品牌画布；仍需系统行级能力的标签和垃圾箱列表保留 `List` / `.swipeActions`，通过 `taskListContentFrame()` 和共享 row inset 对齐同一最大宽度基线。这样避免系统默认浅色 grouped list 在暗色主题下盖住正确文字色，也避免不同任务页各自写死宽度。
- `AppSheetNavigationChrome` 是保留系统 `NavigationStack` 的 sheet 导航外壳：根页保留系统默认标题样式，详情页统一 `.inline` 居中系统标题；导航栏背景保留 SwiftUI / UIKit 系统 scroll-edge 行为，顶部透明、滚动压入内容后由系统 material 接管，不自绘标题、不写死 `UINavigationBarAppearance` 或导航栏背景色。`SettingsSheetView`、`MoodStatsView`、`TagManageView`、`TrashView`、`LanguageSettingsView`、`AppearanceThemeView`、`AboutView` 都挂同一导航契约；`AppearanceThemeView` 的系统标题与设置入口统一为「外观主题」。
- 设置栈内的 `TagManageView`、`TrashView`、`LanguageSettingsView` 已归入任务容器语义，背景使用 `sheetBackground`，行/面板使用 `sheetPanelBackground`，文字使用 `primaryText` / `secondaryText`，不再复用首页品牌画布和气泡 token。
- `backgroundTexture` 已驱动首页主场景背景；`BackgroundTextureSurface` 是网格线、点阵、无、精选和自定义图片的唯一背景内容层，宿主先决定尺寸，本层只在宿主尺寸内绘制 variant。精选背景通过 `FeaturedBackground` 持久化当前内置款式，现有 6 个程序化背景（晨雾湖蓝、雨窗灰绿、纸感暖白、黄昏蜜桃、深海蓝紫、柔光色块），全部按时间轴背景设计，左侧常驻阅读区保持低对比，但选择页只把它们当作背景图展示；精选背景使用独立的 `featuredBackgroundOverlay`，不复用自定义照片遮罩。`HomeSceneBackgroundView` 只由首页 scene host 挂载一次；作用范围是时间轴背后的唯一场景画布，不作用于设置页、编辑器 sheet、气泡卡片、首页热力图自身或其它页面。顶部 chrome 和首页热力图上下文只使用 material / context surface 覆盖在该画布上，不重新铺背景图。
- 自定义背景图片由 `AppearanceThemeView` 通过系统 `PhotosPicker` 选择，`ThemeManager` 在后台压缩后写入 `AppearanceStore` 暴露的 Application Support 固定文件；写入成功后才切到 `.customImage`，写入失败不改变当前背景。UI 测试下使用 `-uiTestBackgroundImageInjection` 暴露调试注入按钮。
- `imageDisplayMode` 已有 UI、状态和持久化，并驱动时间轴气泡图片区在横向缩略图布局和轮播布局之间切换；它只改变照片展示行为，不改变主题颜色语义。
- `AppearanceThemeView` 使用 `TaskPageScrollView` 任务内容列和任务面板分组骨架。模式区两张卡是当前外观状态在暗/亮模式下的总览预览，会同时体现当前背景纹理/精选/自定义图片、导航文字层、FAB/主色和模式色板；颜色区使用响应式 swatch 网格，不允许固定宽度溢出屏幕；背景区改为横向固定卡片，网格/点阵/无/精选/自定义互斥，避免 5 个选项被自适应网格压缩。点击「精选」进入设置栈子页 `FeaturedBackgroundView`，子页是纯背景图库：顶部大预览和 6 个选项卡只显示背景图，不叠时间轴、日期、节点或 moment 卡片；当当前背景来源还不是 `.featured` 时，子页以「精选预览」语义展示记住的精选款式且不显示已选中，点选任一精选后立即切到 `.featured`、显示当前选中并停留在子页。自定义图片在所有预览中都按容器 `scaledToFill + clipped`，不能用原图尺寸反推设置页分组高度。外观页组件消费 `ThemeManager` 和 `AppThemeTokens.resolve`，但不进入 `AppRouter`，也不把首页品牌画布、气泡卡片和 sheet panel 混成同一个容器。

## 已知偏离

| 漂移 | 当前事实 | 当前影响 |
| --- | --- | --- |
| 亮色心情色 | 亮色下除 `.normal` 外仍沿用暗色推导值。 | 不影响主色独立性；亮色效果缺少独立取色事实。 |

## P2b 验证事实

2026-07-08 已运行：

```sh
./scripts/test.sh --only HeatMomentTests/ThemeManagerTests
./scripts/test.sh --only HeatMomentUITests/ThemeSwitchUITests/testSwitchingModeUpdatesModeOptionCardRendering
./scripts/test.sh --only HeatMomentUITests/ThemeSwitchUITests
./scripts/verify.sh
```

结果：`ThemeManagerTests` 执行 7 个测试、0 失败，覆盖自定义背景图写入/修正、五层 token 暗/亮取值、主色派生前景矩阵和商业固定色独立性；`ThemeSwitchUITests` 覆盖切换亮/暗、主色、主色 swatch 不溢出屏幕、外观页分组同宽、主色驱动模式总览同步、背景纹理、自定义背景图、外观页背景预览骨架、图片展示模式，以及设置/外观任务容器在 sheet 已挂载时跟随模式更新；最终 `./scripts/verify.sh` 全部通过。

## P0 验证事实

2026-07-07 已运行：

```sh
./scripts/test.sh --unit
./scripts/test.sh --ui
```

结果：全量单元测试和 UI 测试通过。后续新增测试后，具体测试数量以当次脚本输出为准，不在 current 文档中固化旧数量。

2026-07-07 追加运行：

```sh
./scripts/gen.sh
./scripts/test.sh --only HeatMomentTests/MomentCardLayoutTests
./scripts/test.sh --only HeatMomentTests/TimelineGeometryTests
./scripts/test.sh --only HeatMomentTests/TimelineRailVisibilityTests
./scripts/test.sh --only HeatMomentUITests/DeleteRestorePurgeUITests/testSwipeDeleteMovesToTrash
./scripts/test.sh --only HeatMomentUITests/DeleteRestorePurgeUITests/testSwipingOnTimelineImageDoesNotTriggerDelete
./scripts/test.sh --only HeatMomentUITests/DeleteRestorePurgeUITests/testSwipingOnTimelineCarouselImageDoesNotTriggerDelete
./scripts/test.sh --only HeatMomentUITests/DeleteRestorePurgeUITests/testPreviewIsCardNotPush
./scripts/test.sh --only HeatMomentUITests/LocateFilterUITests/testFilterAbsentMoodShowsEmptyStateThenMarkerRemovalRestoresRecords
./scripts/test.sh --only HeatMomentUITests/TimelineEmptyStateUITests/testFirstLaunchShowsThreeEditableDefaultMoments
./scripts/build.sh
./scripts/lint.sh
```

结果：`MomentCardLayoutTests` 执行 4 个测试、0 失败；`TimelineGeometryTests` 执行 13 个测试、0 失败；`TimelineRailVisibilityTests` 执行 4 个测试、0 失败，覆盖筛选空态不渲染孤立轨道和记录存在时渲染轨道；四条 `DeleteRestorePurgeUITests` 定向 UI 用例均通过，覆盖首页左滑软删除进垃圾箱、横向缩略图和轮播图片区横向手势不触发行级删除、非图片区仍可露出系统删除按钮，以及预览卡片不是 push 页面；筛选空态 UI 和首启默认资料库 UI 均通过。`build` 通过；`lint` 通过并保留既有 warning。

2026-07-08 追加运行一次 P0 视觉取证 UI 流程，截图写入 `/private/tmp/heatmoment-p0-visual/`：

```sh
./scripts/run.sh
./scripts/gen.sh
./scripts/test.sh --only HeatMomentUITests/P0VisualAuditCaptureUITests/testCaptureP0VisualAuditStates
./scripts/verify.sh
```

首次截图审计发现两个实现偏差：热力图年份因 SwiftUI 文本本地化显示为 `2,026`，以及热力图展开并滚动定位后顶部上下文区域有时间轴内容透出。代码修正后重新运行同一取证流程，结果通过。当前截图证据覆盖暗色主页、热力图展开、日期定位、筛选与定位标记并存、左滑删除露出系统删除按钮、亮色主页。审计结论是：节点中心、气泡尾巴和时间轴竖线形成明确绑定；热力图仍属于主页顶部上下文，不是独立漂浮卡片；系统 `.swipeActions` 的轻扫状态满足“阅读单元横向移走、场景轨道保持连续”的 P0 视觉边界。

最终阶段验收运行 `./scripts/verify.sh`，结果全部通过：lint 完成、构建通过、单元测试执行 132 个测试（4 个跳过）且 0 失败、UI 测试执行 37 个测试且 0 失败。lint 仍打印仓库既有 warning，但未阻塞验证。

当前 P0 视觉验收仍有两个非阻塞边界：截图取证是人工视觉审计，不是像素级 snapshot 断言；不同真机尺寸和未来动态内容仍需随对应阶段做抽查。

## Flutter 版只作为语义输入

原 Flutter 项目只作为产品语义输入；SwiftUI current 事实以本仓库 `Sources/HeatMoment/` 与 `Tests/` 为准。Flutter 中的 `showCupertinoSheet`、`GlobalKey + ScrollController`、自定义气泡 shape、Flutter picker 组合、开发者皮肤轴等都不是 SwiftUI 必须照搬的实现细节。
