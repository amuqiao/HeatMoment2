# 12 · 质量保障：性能 / 国际化 / 无障碍 / 测试

> 职责：定义「心绪日记 / 时刻」的非功能质量要求——运行性能、国际化（简中 + 英文）、VoiceOver 语义/交互类无障碍、以及分层测试策略。视觉呈现类要求（对比度、Dynamic Type 布局、视觉无障碍）见 `05-design-system.md`。

## 12.1 性能

- **时间轴分页**：`TimelineHomeView` 用 `FetchDescriptor` + `fetchLimit`/`fetchOffset` 按 `occurredAt` 倒序分页（如每页 30 条），滚动接近底部时追加下一页，避免一次性加载全部记录。
- **图片缓存**：原图经 `externalStorage` 落盘/同步；缩略图另行生成并缓存在本地 `Caches` 目录（不参与 CloudKit 同步），时间轴/预览优先读取缩略图缓存，命中失败才降级到原图现场生成，控制滚动时的解码开销。
- **热力图与统计聚合**：`YearHeatmapView` / `MoodStatsView` 按年份区间用 `#Predicate` 直接在存储层过滤 `occurredAt`，避免把全量 Moment 拉进内存后再遍历统计；对同一年份的重复查询可加轻量内存缓存，随写入操作（新增/编辑/删除 Moment）失效重算。
- **视图 diff**：时间轴列表以 `Moment.id` 作为稳定标识，避免整表重建导致的多余重绘。

## 12.2 国际化（简中 + 英文）

- 全部界面文案（含 `Mood` 名称、默认标签名、Paywall 权益文案）走 iOS17 推荐的 String Catalog（`.xcstrings`），维护 zh-Hans / en 两套。
- 设置页「语言」为应用内语言切换，提供 zh-Hans / English / 「跟随系统」三个选项（`13-open-questions.md` 已裁决），通过 `AppStorage` 记录用户选择的 locale 并注入 `.environment(\.locale, ...)`。
- 日期/时间展示使用 `Date.FormatStyle` 按当前语言环境自动格式化；年度热力图的年份区间（2021–2026）为固定业务范围，不随语言变化。

## 12.3 测试策略

- **单元测试**：`Mood` 枚举顺序/emoji 映射的快照测试（防止契约被误改）；免费限额（10/3/3）边界值测试；Moment 软删除状态机测试（删除→恢复→彻底删除的字段流转正确性）。
- **StoreKit 测试**：使用 `StoreKitTest` 框架 + `.storekit` 配置文件，覆盖购买成功/失败、恢复购买、核销码、订阅到期后自动降级为免费态等场景。
- **UI 测试（XCUITest）**：新建 Moment 全流程、首页左滑删除进垃圾箱、垃圾箱恢复、触发限额弹出 Paywall 等关键路径。
- **快照测试**：时间轴卡片、心情统计条形图在深/浅色模式与中/英文下的截图比对（与 `05-design-system.md` 视觉规格联动验收）。
- **CloudKit 同步测试**：双模拟器/双 iCloud 沙盒账号验证跨设备增删改同步与 `09-icloud-sync.md` 冲突处理一节所述冲突场景的实际表现。

## 12.4 无障碍（VoiceOver 语义/交互类）

- 情绪选择：每个候选项 `accessibilityLabel` 为完整语义（「情绪：正常」），选中态用 `accessibilityValue`/`isSelected` trait 而非仅靠视觉勾选。
- 时间轴卡片：`accessibilityElement(children: .combine)` 合并子视图为一次朗读，避免逐个子元素碎片化朗读。
- 滑动动作（首页删除、垃圾箱恢复/彻底删除、标签管理删除）：均提供对应 `accessibilityCustomAction`/`accessibilityAction(.delete)`，保证不依赖手势也能完成操作。
- 图片查看器：图片 `accessibilityLabel` 为「照片，第 N 张，共 M 张」占位描述，不做自动生成 alt-text（避免额外网络请求与隐私顾虑）。
- 隐私锁页面：`accessibilityAddTraits(.isModal)`，防止 VoiceOver 焦点穿透到底层敏感内容。
- Paywall：权益条目完整朗读对比文案（「发布无限的心情日记，普通用户最多只能发布 10 篇日记」）。
- Dynamic Type 结构性要求：所有文本使用语义字体（如 `.font(.body)`/`.headline`）而非固定 point size，为 `05-design-system.md` 的排版实现提供可响应系统字号的接口层约束（具体视觉呈现由 `05-design-system.md` 负责）。
