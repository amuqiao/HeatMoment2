# 13 · 开放问题与决策记录

> 职责：汇总「心绪日记 / 时刻」复刻过程中的**产品类**开放问题及其裁决状态。本清单已于一轮集中确认后更新，分四组：✅ 已裁决 / ☑️ 采纳默认 / 🔧 开发阶段实测 / ❓ 仍待定。「落实位置」列指向具体落地的分文件。
>
> **架构/技术类决策**（架构范式、集中路由、模态层叠呈现、最低 iOS 版本、并发模型、popover 二义等）已在生产就绪评审中拍板，记录在 `14-design-decisions.md`（ADR），不在本文重复。

## ✅ 已裁决（产品拍板，正文已落实）

> 下列已裁决项依产品公理层《[产品心智模型](../product-mental-model.md)》与阶段开工前用户裁决记录整理；其对应的架构落地（模态层叠、就地半屏 sheet、字段就近浮窗、主页顶部上下文区）见 `14-design-decisions.md`、`08-architecture.md` 与 `implementation-plan.md`。

| # | 问题 | 裁决 | 落实位置 |
|---|---|---|---|
| 23 | 标签创建入口归属 | **标签不允许在编辑器里临时创建，继续只在设置页标签管理集中创建/重命名/删除**。编辑器 `TagPickerView` 和首页筛选 `FilterPanelView` 只消费已有标签，不提供新增入口。 | ../product-mental-model.md、03-user-flows.md、04-screen-specs.md、08-architecture.md |
| 22 | 首页删除手势与时间轴操作态 | **首页 Moment 左滑软删除进垃圾箱，无确认**；交互优先使用 SwiftUI/iOS 成熟 swipe action，轻扫露出删除、继续滑动按钮拉长。左滑时日期、心情节点、moment 气泡作为一个记录整体左移，不能让时间轴视觉断裂。 | 03-user-flows.md、04-screen-specs.md、implementation-plan.md |
| 21 | 热力图「选月」是否落地 | **落地**。月份入口隐藏在热力图月份标签/月份区域中；点月只作为时间定位 anchor，不筛选；当前月份区域显示与设置页主色一致的轻微透明蒙层；锚点命中该月在当前筛选口径下的真实记录。 | 03-user-flows.md、04-screen-specs.md、08-architecture.md、implementation-plan.md |
| 19 | 多标签筛选的组合逻辑、心情筛选单/多选 | **标签多选、彼此 AND（交集）；心情单选；标签与心情之间 AND** | 04-screen-specs.md、03-user-flows.md |
| 18 | 情绪命名 | 以真机为准的 **8 情绪：正常/开心/难过/焦虑/恐惧/愤怒/厌恶/激励**（清除「平静/低落/害怕/生气/厌烦/有动力」等残留旧名） | 06-domain-model.md、04-screen-specs.md、../product-mental-model.md |
| 17 | 单条预览的呈现方式 | **弹出阅读卡片**（在时间轴之上浮起、进入任务卡片栈），**非** push 页面跳转 | 03-user-flows.md、04-screen-specs.md、14-design-decisions.md |
| 16 | 编辑页字段选择用 sheet 还是就近浮窗 | **就近浮窗**：日期/时间/情绪/标签等编辑页字段选择锚定触发点、带尖角、背景不下沉、不入层级栈，跨设备（含 iPhone）保持浮窗、不降级半高 sheet；首页标签/心情筛选已另行裁决为就地半屏 sheet，不归入本问题。完整任务（新建/编辑、预览、设置、Pro、新建标签）才用可层叠的任务卡片栈 | 04-screen-specs.md、14-design-decisions.md、../product-mental-model.md |
| 9 | 默认预置标签集合 | **工作 / 生活 / 健康**（预置即占满免费 3 标签额度，可接受） | 07-data-persistence.md |
| 8 | 一条 Moment 挂几个标签 | **多选**（Moment↔Tag 多对多） | 04-screen-specs.md、07-data-persistence.md |
| 6 | 垃圾箱内 Moment 是否计入 10 篇上限 | **计入**（软删除不释放额度，须彻底删除才腾名额） | 03-user-flows.md、07-data-persistence.md |
| 5 | Pro 订阅方案 | **月订阅 ¥6 + 终身买断**（终身为新增，超出原 App） | 11-monetization.md、06-domain-model.md、04-screen-specs.md、05-design-system.md |

## ☑️ 采纳默认（B 档，未提异议即生效）

| # | 问题 | 采纳的默认值 | 落实位置 |
|---|---|---|---|
| 3 | 外观偏好/面容开关是否跨设备同步 | **均不同步**（设备本地偏好） | 07-data-persistence.md、10-security-privacy.md |
| 4 | 语言集合 & 跟随系统 | **仅简中/English + 提供「跟随系统」** | 12-quality-assurance.md |
| 7 | 未保存表单二次确认形式 | 系统 `Alert`：「放弃编辑 / 继续编辑」 | 03-user-flows.md |
| 10 | TrashView 在设置流入口位置 | 设置「分组卡片 A」，与「标签」同级 | 02-information-architecture.md、04-screen-specs.md |
| 11 | Pro 用户态横幅呈现 | 替换为「已是 Pro 会员」态；误触 Paywall 提示已订阅 | 04-screen-specs.md |

## 🔧 开发阶段实测（非产品决策，实现时验证）

| # | 问题 | 处理方式 |
|---|---|---|
| 1 | iCloud 未登录/关闭时同步行文案与降级 UI | 实现时补文案，默认「未开启 iCloud」（见 09-icloud-sync.md） |
| 2 | SwiftData 是否暴露足够 CloudKit 同步事件粒度 | 实测，不足则启发式兜底（见 09-icloud-sync.md） |
| 12 | 视觉规格色值多处 WCAG 不达标（亮色红字 3.23:1、FAB 白图标 2.99:1 等） | 实现前用对比度工具按 05-design-system.md 视觉无障碍一节复核调整 |
| 13 | 日期选中圆用主色还是主文本色 | 真机实测区分（见 04-screen-specs.md、05-design-system.md） |
| 20 | 时间轴定位命中行高亮的具体透明度 | 05-design-system.md §5.7 只给出「主色 12–16% 透明度叠加」的区间；阶段5实现取 **14%**（`TimelineViewportView.locateHighlightOpacity`），落在区间中点，待真机截图复核后如需调整只改这一处常量 |

## ❓ 仍待定（新增，需后续确认）

| # | 问题 | 说明 |
|---|---|---|
| 14 | **终身买断定价** | 月订阅 ¥6 已知，终身买断价格未定，需产品定价后填入 11-monetization.md、06-domain-model.md 与 Paywall 文案 |
| 15 | **终身买断的 Paywall 视觉** | 真机仅单一月订阅布局，双方案的价格区呈现（方案卡/分段选择器）需原型阶段设计（见 04-screen-specs.md、05-design-system.md） |
