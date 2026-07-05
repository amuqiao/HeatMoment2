# 07 数据模型与持久化

> **本文职责**：定义「时刻」App 的本地持久化选型、数据实体与字段契约、CloudKit 兼容约束，以及不接入云同步的本地偏好与订阅缓存结构。实体的情绪字段以 `06-domain-model.md` 的 `Mood` 契约为准；iCloud 同步方案见 `09-icloud-sync.md`；订阅判定逻辑见 `11-monetization.md`；软删除生命周期的用户流程见 `03-user-flows.md`。

---

## 1. 选型理由

采用 **SwiftData**（而非手写 Core Data / GRDB / Realm）：
- 项目为 iOS 17+ 全新起点，无历史数据迁移负担，可以直接使用 SwiftData 的 `@Model` 声明式建模，减少样板代码 `[设计决策]`。
- SwiftData 底层复用 Core Data + `NSPersistentCloudKitContainer` 能力，对「本地优先 + 用户私有 iCloud 同步」这一已确认的产品定位是官方一等公民支持路径，避免自建同步协议 `[设计决策]`。
- 与 SwiftUI `@Query` 原生绑定，`TimelineHomeView`/`MoodStatsView`/`YearHeatmapView` 等以数据驱动的列表和聚合视图可以直接声明式取数，减少手写 ViewModel 胶水代码 `[设计决策]`。

---

## 2. CloudKit 兼容约束（贯穿本节所有实体设计必须遵守）

1. 所有属性必须有默认值或声明为 `Optional`（CloudKit 字段无 NOT NULL 约束）。
2. 不支持 `@Attribute(.unique)` 唯一约束；唯一性（如标签重名）必须在应用层查询校验后再插入。
3. 关系必须是可选的，且删除规则不支持 `.deny`，只能用 `.cascade` / `.nullify`。
4. 不支持模型内建复合唯一索引。
5. 大二进制数据（图片）应使用 `@Attribute(.externalStorage)`，由框架转存为 CKAsset，避免单字段超过 CKRecord 约 1MB 限制。
6. 枚举等自定义类型 CloudKit schema 不识别，必须以基础类型（如 `Int` rawValue）落库，配合计算属性对外暴露强类型（对应 `06-domain-model.md` 的 `Mood` 契约）。
7. Schema 演进只能「新增可选/带默认值字段」保持向前兼容；删除字段/改类型需要 `SchemaMigrationPlan` 做版本化迁移，CloudKit 记录类型本身不支持重命名字段。

---

## 3. Moment

```swift
@Model
final class Moment {
    var id: UUID = UUID()   // 本地唯一标识；不加 @Attribute(.unique)——CloudKit 下 .unique 不生效
                            // （见第 2 节第2条），唯一性由 UUID 值本身保证，加了反而误导

    var title: String = ""
    var bodyText: String = ""                     // 正文；避免用 body 以免与 SwiftUI 语义混淆

    /// 发生时间：用户可编辑的"事情发生的时间"，支持任意过去/未来日期，用于补记
    var occurredAt: Date = Date.now

    /// 系统记录创建时间：审计用途，不可编辑，不参与排序展示
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// 情绪：落库为 Int rawValue（CloudKit 约束第 2 节第6条），对外通过计算属性暴露 Mood
    var moodRawValue: Int = Mood.normal.rawValue
    var mood: Mood {
        get { Mood(rawValue: moodRawValue) ?? .normal }
        set { moodRawValue = newValue.rawValue }
    }

    @Relationship(deleteRule: .nullify, inverse: \Tag.moments)
    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade, inverse: \MomentImage.moment)
    var images: [MomentImage] = []

    /// 软删除生命周期字段。
    /// 存储列用 deletedFlag，对外以计算属性 isDeleted 暴露（同 moodRawValue→mood 模式）：
    /// 规避 SwiftData 对 `is` 前缀 Bool 存储属性的 KVC 缺陷（save() 后会被静默重置为 false，已最小复现）。
    /// **`#Predicate` 一律引用存储列 `deletedFlag`，不引用计算属性 isDeleted。**
    var deletedFlag: Bool = false
    var isDeleted: Bool {
        get { deletedFlag }
        set { deletedFlag = newValue }
    }
    var deletedAt: Date? = nil
}
```

- 排序/分页均以 `occurredAt` 为主键（时间轴、热力图、统计都按发生时间而非创建时间组织，符合「补记」语义）`[观测确认]`。
- 免费额度计数（10 篇）统计**所有尚未物理删除的记录（含垃圾箱内 `isDeleted==true` 的）**（已裁决，软删除与恢复的用户流程见 `03-user-flows.md`）：额度计数不按 `isDeleted` 过滤，只有在垃圾箱彻底删除后才从计数移除；而时间轴列表展示仍只查未删除的记录。二者是不同查询，勿混用同一 `FetchDescriptor`（谓词层引用存储列 `deletedFlag`，见上方 `Moment` 注释）。限额数值以 `06-domain-model.md` 为唯一权威。

### 3.1 热力图 / 日期着色的聚合口径

热力图（`YearHeatmapView`，及 `MoodStatsView` 内「心情日期分布」卡）中某一天日期格的着色遵循以下聚合口径（本节为口径描述，非实现代码）`[设计决策,依公理1（着色用心情色）；跟随当前筛选口径但不改数据集合属公理2]`：

- **取色规则**：某一天的日期格心情色 = 该日**未软删除**（`isDeleted==false`）时刻中、`occurredAt` **最晚一条**时刻的 `mood` 对应的心情色（`mood`→心情色映射见 `05-design-system.md` §5.4 与 `06-domain-model.md` §1.4）。
- **按发生时间归日**：以 `occurredAt`（而非 `createdAt`）判定一条记录属于哪一天，与时间轴、统计的「按发生时间组织」口径一致。
- **空态**：某天无未软删除记录时，日期格为空灰态，不着任何心情色。
- **与筛选正交**：热力图跟随当前筛选口径展示「当前条件下」的年度分布，但单个日期格的着色规则本身不变（仍取当日命中记录中 `occurredAt` 最晚一条的心情色）。

---

## 4. Tag

```swift
@Model
final class Tag {
    var id: UUID = UUID()
    var name: String = ""            // 唯一性由应用层保存前查重保证，见第 2 节第2条
    var createdAt: Date = Date.now

    var moments: [Moment] = []       // 反向关系，见 Moment.tags 的 inverse
}
```

- 默认标签在首次启动预置写入 **工作 / 生活 / 健康** 三个（已裁决）。注意副作用：免费标签上限为 3，预置 3 个即占满免费额度——新用户要自建标签需先删除已有标签或升级 Pro，此为已知且可接受的取舍。
- 标签删除只做 `moments` 关系解除（借助 `.nullify` 规则），不影响 `Moment.isDeleted`，与 Moment 软删除生命周期完全独立 `[观测确认]`。
- 免费额度计数（3 个标签）以 `Tag` 表总行数为准（标签无软删除概念，删除即物理删除）。

---

## 5. MomentImage（图片存储策略）

```swift
@Model
final class MomentImage {
    var id: UUID = UUID()
    var sortIndex: Int = 0            // 追加顺序，决定横向缩略图排列
    var createdAt: Date = Date.now

    /// 原图数据，使用 externalStorage 交由 SwiftData/CloudKit 转存为文件/CKAsset，
    /// 而非内联在 CKRecord 字段中（见第 2 节第5条）
    @Attribute(.externalStorage) var imageData: Data = Data()

    var moment: Moment?
}
```

- **策略**：原图（压缩后的 JPEG/HEIC 转 JPEG，控制单张体积）通过 `externalStorage` 交给框架管理落盘与 CloudKit 资产同步；时间轴卡片和缩略图**不直接读取原图**，而是本地维护一份缩略图磁盘缓存（如 `Caches/thumbnails/{id}.jpg`），缓存不参与 CloudKit 同步（可随时基于原图重新生成，无需占用同步带宽）。
- 每篇 Moment 的免费照片上限（3 张）以 `images.count` 校验，超限拦截发生在「追加照片」操作发生时（记录流程见 `03-user-flows.md`，限额数值见 `06-domain-model.md`）。
- **图片压缩规格**（生产必备，`[设计决策]`）：入库前统一转 JPEG（HEIC 解码后重编码），长边上限约 2048px、质量 ~0.8，单张目标 < 500KB，避免原图直接进 CKAsset 撑爆 iCloud 配额与同步带宽；具体阈值实现阶段按真机实测微调。
- **缩略图缓存清理**（生产必备，`[设计决策]`）：`Caches/` 目录可被系统回收，读取时需「命中缓存则用、未命中则从原图现场生成并回写」；Moment 彻底删除时同步清理其缩略图；缓存上限 ~100MB 或最近 300 条，超限按 LRU 淘汰（`[设计决策]`，可实测微调），缓存生成/读写用 `actor` 封装保证并发安全（并发模型见 `08-architecture.md` 第 5 节）。

---

## 6. 外观偏好（本地设备级，不接入 CloudKit）

```swift
/// 非 SwiftData @Model，采用 UserDefaults / AppStorage 承载，
/// 原因：外观是"设备呈现偏好"而非需要跨设备一致的"内容数据"，
/// 且避免把展示层状态卷入 CloudKit 冲突解决范围（见 09-icloud-sync.md）
struct AppearancePreference: Codable {
    var colorScheme: ColorSchemeOption   // .dark / .light
    var accentColorID: AccentColorOption // 紫色/红色/橙色/绿色/青色/紫罗兰，默认紫罗兰
    var backgroundGridStyle: GridStyleOption   // 网格线/点阵/无
    var photoDisplayStyle: PhotoDisplayOption  // 滚动/轮播
}
```

主题参数的语义与取色见 `05-design-system.md`；外观偏好写入需返回成功/失败结果，供 UI 层在不回滚视觉的前提下展示保存失败提示（乐观更新交互见 `05-design-system.md`）。外观偏好已采纳默认：不跨设备同步（设备本地偏好），追溯见 `13-open-questions.md`。

---

## 7. 订阅状态缓存

```swift
/// 本地缓存，不接入 CloudKit（Apple 账号层面的 entitlement 已由 StoreKit
/// 自身在同一 Apple ID 下跨设备生效，无需再造一份 CloudKit 同步，避免双重数据源）
struct SubscriptionStateCache: Codable {
    var isPro: Bool                 // = subscriptionActive || lifetimeUnlocked（OR 结果，Pro 判定见 11-monetization.md）
    var subscriptionActive: Bool    // 月订阅当前有效
    var lifetimeUnlocked: Bool      // 终身买断已购（[设计决策，超出原 App]）
    var productID: String?
    var expirationDate: Date?       // 仅对月订阅有意义；终身买断为 nil
    var originalTransactionID: String?
    var lastVerifiedAt: Date
}
```
- 每次冷启动 / 回前台时用 `Transaction.currentEntitlements` 重新核对并覆盖该缓存，缓存只用于减少每次开屏的判断延迟，不作为最终授权依据（最终依据永远是 StoreKit 的 `Transaction`）。StoreKit 集成与购买/恢复/核销码流程见 `11-monetization.md`。
