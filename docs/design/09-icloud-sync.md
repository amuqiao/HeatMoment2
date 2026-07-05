# 09 · iCloud 同步

> 职责：定义「心绪日记 / 时刻」如何借助 SwiftData + CloudKit 把本地数据同步到用户个人 iCloud 私有库，包括同步方案、状态展示、离线优先原则、图片资产同步、冲突处理，以及与「不收集数据」隐私立场的一致性。

## 9.1 方案

- 使用 SwiftData 的 CloudKit 集成能力，`ModelConfiguration` 指定私有数据库容器（`iCloud.<bundle-id>`），`Moment` / `Tag` / `MomentImage` 三个实体参与同步；`AppearancePreference`、`SubscriptionStateCache` 不参与（原因见 `07-data-persistence.md` 外观偏好与订阅状态缓存两节）。
- 需要在 Xcode 项目开启 iCloud + CloudKit 能力（entitlements），并声明容器标识符。

## 9.2 「已同步」状态展示

设置页「iCloud 数据同步」行右侧展示「已同步 >」 `[真机确认]`。SwiftData 目前未提供高层公开 API 直接暴露「同步中/已同步/失败」细粒度状态，工程实现建议：
- 监听底层 Core Data 的 `NSPersistentCloudKitContainer.eventChangedNotification`（若可通过 `modelContainer` 访问到底层 container），据此推导「同步中 / 已同步 / 失败」；
- 若该事件无法稳定拿到，退化为启发式状态：以「最近一次本地写入 + 网络可达性」推断展示「已同步 / 同步中 / 离线，将在联网后同步」三态。
此处标记为**开放问题**：需要在实现阶段验证 SwiftData 是否暴露足够的 CloudKit 同步事件粒度，必要时准备启发式兜底方案 `[设计决策]`。

## 9.3 离线优先

本地 SwiftData 存储永远是唯一可信的读写路径；App 全部核心功能（记录、浏览、筛选、热力图、统计、垃圾箱）必须在无网络/未登录 iCloud 情况下完整可用，CloudKit 同步是后台异步的「锦上添花」能力，不阻塞任何 UI 交互 `[观测确认]`。

## 9.4 图片资产同步

`MomentImage.imageData` 的 `externalStorage` 属性由框架自动映射为 CKAsset 参与同步；本地缩略图缓存（见 `07-data-persistence.md` MomentImage 图片存储策略）不同步，换设备后按需从已同步的原图重新生成。

## 9.5 冲突处理

- 结构化字段冲突（同一 Moment 被两台设备同时编辑）依赖 Core Data/CloudKit 默认合并策略（属性级 trump，通常配置为最后写入者优先），个人日记场景下多设备并发编辑同一条记录概率低，可接受该默认策略 `[设计决策]`。
- 软删除冲突边缘场景（设备 A 彻底删除、设备 B 同时执行恢复）按最后到达 CloudKit 的写入生效，属于可接受的极端情况，不做额外锁机制 `[设计决策]`。

## 9.6 与「不收集数据」隐私声明的一致性

CloudKit 私有数据库归属用户自己的 Apple 账号容器，开发者无法访问其中内容，因此启用 iCloud 同步与「App 不收集用户数据」的隐私立场并不冲突：数据始终只流转于「用户设备 ↔ 用户自己的 iCloud」之间，不经过任何自建服务器 `[观测确认 + 设计决策]`。此结论同时支撑 `10-security-privacy.md` 隐私锁的隐私一致性表述。
