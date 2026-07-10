# Moodments 数据生命周期实现计划

本文是当前主动计划，只记录尚未完成的目标架构、实施顺序和验收条件。已落地事实进入 [`../current/`](../current/README.md)；产品语义以 [`../product-mental-model.md`](../product-mental-model.md) 为准。

## Planning Position

Moodments 是单机优先、小而美的个人日记 App。数据架构必须可靠、可恢复、可验证，但不能膨胀成账号系统、云备份平台或多人协同系统。

### 用户心智模型

```text
记录默认保存在本机
  -> App 自动保留最近 3 个本机恢复点
  -> 用户可从恢复点恢复，但不能删除恢复点
  -> 用户可导出 Markdown / PDF 阅读副本
  -> 后续可使用系统 iCloud 在自己的设备间同步
```

- App 使用无需登录，不引入 Moodments 账号。
- 本机保存是默认事实，不是用户要选择的模式。
- iCloud 同步依赖系统 Apple ID，只是后续跨设备收敛通道，不是 App 登录，也不叫云端备份。
- 自动恢复点是 App 内本机恢复点，最多保留 3 个，系统自动维护，用户只查看和恢复。
- Markdown / PDF 导出是只读副本，不用于恢复，不参与 iCloud 同步。

### 开发者心智模型

```text
UI / ViewModel
  -> LibraryRepository
      -> Canonical SQLite Store
          -> domain records / tombstones / asset metadata
          -> mutation_log
          -> derived query tables
          -> recovery_points / restore_jobs / export_jobs
          -> sync_outbox / sync_checkpoint / conflict_record
      -> File Asset Store
      -> Automatic Recovery Point Service
      -> Export Service
      -> Optional Future iCloud Sync Service
```

- 本地 canonical store 是读写权威；SwiftData 只是 current 事实和迁移来源，不是目标权威。
- projection 不做第二权威；首选同一 SQLite 库里的 derived tables/views 或可重建查询层。
- `mutation_log` 记录本地事实；`sync_outbox` 记录可重试同步意图；两者不能混用。
- iCloud 同步后置为独立计划，不能阻塞本地创建、编辑、删除、恢复、导出。

### 非目标

- 不做 App 账号、登录态、服务端用户模型或自建后端。
- 不做多人协作、实时协同编辑或共享资料库。
- v1 不做用户手动删除恢复点，也不做复杂 merge restore。
- v1 不把外部 `.moodmentsbackup` 文件作为主恢复模型；如需可分享备份文件，后续在自动恢复点稳定后单独设计。

## Current Baseline

- 当前 App 已有 SwiftData `Moment` / `Tag` / `MomentImage` 模型、`@ModelActor` repository、软删除/恢复/彻底删除、照片压缩、缩略图缓存、设置页 iCloud 状态行和基础测试。
- 当前生产启动路径会尝试 SwiftData + CloudKit 私有库容器，不可用时回退本地 SwiftData 容器。
- 当前 `SyncStatusService` 只是启发式状态展示：`cloudKitEnabled + 网络可达性 + 最近本地写入时间`，不是 CloudKit import/export 事件，也不表达未登录 iCloud、账号变化、冲突、失败重试或恢复进度。
- 当前 UI 用户写入入口已有过渡版 `LocalLibraryMutationService`：它仍委托 SwiftData repository，但已收口本地写入标记、稳定恢复点、安全恢复点、缩略图失效和时刻/标签创建额度终判。它是迁往 canonical store 前的应用服务边界，不是最终存储权威。
- 当前已有 SwiftData 过渡版本机自动恢复点：最多 3 个、设置页列表、恢复预览、pending restore staging、恢复已排队阻断页、冷启动 replace、成功/失败反馈、稳定变更节流触发和高风险操作前安全点。它还不是目标 canonical store 下的最终 recovery catalog / asset pin 方案。
- 当前已有 GRDB canonical store、repository 骨架、`CanonicalLibraryRuntime` 装配类型，以及 SwiftData -> canonical baseline 导入器测试；当前 App 启动不打开 canonical 持久库，它们尚未切入生产 UI 读写路径，也不做 SwiftData + GRDB 双写。
- 当前没有完整数据生命周期：无 canonical UI 读写路径、无 canonical recovery catalog、无持久 outbox、无自定义同步状态机、无 Markdown/PDF 导出任务、无真实 iCloud 多设备验收。
- 当前 SwiftData 是过渡实现和 UI 可用路径，不作为目标架构里的最终数据权威。

## Mature Choices

| 需求 | 采用方案 | 边界 |
| --- | --- | --- |
| 本地权威、事务、迁移、查询 | SQLite + GRDB 候选 | 阶段 0 冻结；若不用 GRDB，必须记录替代方案如何覆盖迁移、事务、观察和测试。 |
| 图片与大文件 | Content-addressed file asset store | 文件归 App 管理；SQLite 只存 metadata、hash、引用和 pin。 |
| 崩溃后恢复 | SQLite transaction + durable job tables | 写入、恢复、导出、同步都用持久状态；不靠内存队列。 |
| 本机自动恢复点 | Recovery point catalog + atomic snapshot/replace | v1 最多 3 个恢复点；用户不可删除。 |
| PDF 导出 | 系统 PDF renderer | 优先用 Apple 系统能力，不引入重型排版框架。 |
| Markdown 导出 | 自有轻量 renderer | 从一致性快照生成文本和相对图片目录。 |
| iCloud 同步 | CloudKit private database + single custom zone | 后续独立计划；只做个人多设备同步，不做协同平台。 |
| 外部备份文件 | 后续可选 ZIP package | 只有明确要分享/迁移备份文件时才引入 ZIP 依赖，避免 v1 范围膨胀。 |

## Core Data Model

阶段 0 必须冻结最小 schema。字段名可在设计层微调，但职责不能合并。

| 表 / 对象 | 职责 |
| --- | --- |
| `library_metadata` | `libraryID`、schema version、app version、`deviceID`、当前 `syncEpoch`、上次迁移状态。 |
| `moment_record` | Moment 标题、正文、发生时间、心情、生命周期状态、revision。 |
| `tag_record` | 标签名称、revision、生命周期。 |
| `moment_tag_link` | Moment-Tag 关系，支持标签 AND 筛选和同步冲突判断。 |
| `asset_record` | 原图资产 metadata：`assetID`、hash、MIME、尺寸、字节数、引用状态。 |
| `tombstone_record` | 删除终态和 purge 传播所需信息。 |
| `mutation_log` | 本地不可变事实：创建、编辑、软删、恢复、彻底删除、标签变更。 |
| `sync_outbox` | 后续 iCloud 计划使用的可重试出站任务，携带幂等 key、目标 revision、重试状态。 |
| `sync_checkpoint` | 后续 iCloud 计划使用的 CloudKit token、Apple ID 边界状态、server metadata。 |
| `conflict_record` | 无法自动合并的正文、照片、标签关系、删除冲突；v1 先服务本机恢复/删除边界，iCloud 冲突后续扩展。 |
| `recovery_point` | App 自动恢复点 catalog，最多保留 3 个。 |
| `restore_job` | staging、校验、replace、失败恢复的持久状态。 |
| `export_job` | Markdown/PDF 导出任务状态、目标、进度和失败原因。 |

### Identity Model

| ID / 版本 | 语义 |
| --- | --- |
| `libraryID` | 一个本机资料库的稳定身份。v1 replace restore 后保持当前本机 library，不从恢复点覆盖。 |
| `recordID` | Moment、Tag、Link、Asset metadata 的稳定业务 ID。 |
| `assetID` | 原图资产 ID，首选内容 hash 或稳定 UUID + hash。 |
| `deviceID` | 本设备写入来源，持久化保存，不进入用户可编辑数据。 |
| `mutationID` | 单次本地事实 ID。 |
| `operationID` | 单次同步意图的幂等键。 |
| `recordRevision` | 业务记录版本，用于并发更新和冲突检测。 |
| `serverChangeTag` | CloudKit 服务器版本标记，仅用于 CloudKit 乐观并发。 |
| `syncEpoch` | 后续同步基线世代。v1 restore 先写入新世代占位，iCloud 计划再消费它。 |
| `tombstoneState` | `active / softDeleted / purgePending / purged`。 |

## Data Ownership

| 数据 | 目标权威 | 本地 | iCloud | 自动恢复点 | 导出 |
| --- | --- | --- | --- | --- | --- |
| Moment 文本/时间/心情/生命周期 | Canonical record | 是 | 是 | 是 | 是 |
| Tag 与 Moment-Tag 关系 | Canonical record/link | 是 | 是 | 是 | 是 |
| Moment 原图 | Content-addressed asset | 是 | 是 | 是 | 可选复制 |
| 缩略图 | 派生缓存 | 是，Caches | 否 | 否 | 否 |
| 外观偏好/背景图 | 本机偏好 | 是 | 否 | 否 | 否 |
| 隐私锁/语言/订阅缓存 | 本机偏好或系统服务 | 是 | 否 | 否 | 否 |
| `mutation_log` | 本地审计与重建依据 | 是 | 否 | 可选诊断 | 否 |
| `sync_outbox` / checkpoint | 同步状态 | 是 | 否，结果同步为 record | 否 | 否 |
| 自动恢复点 | 本机恢复能力 | 是 | 否 | 是 | 否 |
| Markdown/PDF 文件 | 用户选择位置的副本 | 用户选择 | 否 | 否 | 是 |

## Lifecycle Design

### 写入

1. UI 提交创建、编辑、标签变更、删除、恢复或彻底删除。
2. Repository 在单个 SQLite 事务中写入 canonical record、asset metadata 和 `mutation_log`。
3. 同事务更新 derived query tables 或标记 projection 需要重建。
4. UI 从本地 query layer 立即刷新。
5. 后续 iCloud 计划可从 `mutation_log` 派生 `sync_outbox`；v1 本地写入不等待远端。

本地事务失败必须直接报错。v1 不因 iCloud 不可用影响本机写入。

### 删除

```text
active
  -> softDeleted
  -> purgePending
  -> purged
```

- 软删除：移出主时间轴，保留内容、资产和关系，垃圾箱可恢复。
- 恢复：写恢复 mutation，保留原发生时间、心情、标签和照片。
- 彻底删除：先进入 `purgePending`，记录不可恢复意图；iCloud 阶段需传播终态。
- `purged` 是最高优先级终态。旧设备离线编辑同一记录时，不得复活记录，只能进入冲突或丢弃旧 mutation。
- 资产 GC 只能在 purge 终态、无恢复点 pin、无 staging/export/sync pin、无引用审计问题时执行。

### 自动恢复点

自动恢复点是 v1 主恢复模型，不是用户手动管理的备份文件。

- App 自动创建和维护恢复点，最多保留 3 个。
- 用户可在设置里看到恢复点列表：创建时间、记录数、标签数、照片数、App/schema version、原因。
- 用户可选择某个恢复点进入恢复预览。
- 用户不能删除恢复点；没有滑删、菜单删除或批量管理。
- 保留策略由系统维护：创建新恢复点成功后，按 `createdAt` 淘汰最旧的超额恢复点。
- 被保留恢复点引用的 asset 必须被 pin；恢复点淘汰后才允许释放对应 pin。
- 创建恢复点失败时，任何 replace restore 或 destructive migration 必须中止。

触发器首版保持少而明确：

- destructive schema migration 前。
- replace restore 前。
- 用户写入成功后按稳定变更节流创建：时刻保存、软删除、标签新增/重命名等普通写入不阻塞业务成功；当前 SwiftData 过渡版阈值为 5 分钟。
- 高风险操作前创建安全点：replace restore、垃圾箱恢复、彻底删除、标签删除。安全点创建失败时，对应高风险操作中止。

稳定变更阈值只能影响何时多建恢复点，不能影响普通写入成功与否；安全点属于高风险操作闸门，失败时不得继续执行后续破坏性替换或删除。

#### 恢复点载荷与身份契约

阶段 0 必须冻结恢复点的最小可恢复载荷：

- `libraryID` 在 v1 replace restore 后保持为当前本机 library，不从恢复点覆盖；恢复点记录原始 `sourceLibraryID` 仅用于诊断。
- 恢复点包含 SQLite 一致性快照、schema version、App version、创建原因、记录/标签/照片计数。
- 恢复点包含 asset manifest：`assetID`、hash、字节数、相对文件位置和 pin 信息。
- 恢复点不包含缩略图、语言、隐私锁、订阅缓存、外观偏好或 iCloud token。
- 恢复点校验失败时在列表中显示为不可恢复状态，不静默隐藏；系统后续可在保留策略中淘汰它，但用户不能手动删除。

### 恢复

首版只支持从 App 自动恢复点 `replace library`，不支持 merge restore。

1. 用户从 `自动恢复点`详情页选择恢复点。
2. 进入恢复预览：恢复点时间、记录数、标签数、照片数、会替换当前资料库。
3. 执行前创建新的安全恢复点；失败则中止。
4. 将目标恢复点导入 staging store 并校验 schema、引用完整性、asset hash。
5. 使用 atomic replace 切换 canonical store。
6. replace 后重建 projection、按需再生缩略图。
7. 写入新的 `syncEpoch`，并清空后续同步计划会消费的旧 outbox/token 占位。
8. 清理 staging pin 和临时文件。

恢复失败不能破坏当前 library。staging 成功但 replace 前崩溃，重启后必须能明确回滚或继续到安全终态，不能半替换。

### Markdown / PDF 导出

导出是只读副本，不承担备份/恢复语义。

- 导出从一致性快照读取，不能直接拼活跃 UI 查询结果。
- Markdown：按全部、当前主页筛选或日期范围生成 `.md`，图片复制到相邻 `assets/` 并使用相对链接。
- PDF：按同一查询生成阅读文档，照片可嵌入，长文分页稳定。
- `export_job` 状态：`queued / rendering / writing / completed / cancelled / failed`。
- 导出文件不回写 canonical store，不进入 iCloud，不创建恢复点。
- 用户取消、目标冲突、写权限失败、磁盘不足或崩溃后，canonical store 不变，临时文件可清理。

### iCloud 同步

iCloud 是个人多设备同步增强，后置于本地可靠核心。

- 使用用户私有 iCloud 数据库，不引入自建后端。
- 不做 App 登录；Apple ID 只属于系统同步边界，不进入 canonical domain。
- 首版单 library、单 custom zone，避免多 zone token 和恢复路径复杂化。
- 保存 CloudKit change token、server record changeTag、失败原因和上次成功同步时间。
- 前台启动、前台恢复、网络恢复和用户手动重试驱动补偿同步；iOS 后台任务只是 best-effort。

Apple ID / iCloud 边界必须可见：

| 状态 | 用户语义 | 行为 |
| --- | --- | --- |
| `localOnly` | 仅本机保存 | App 完整可用，不显示登录门槛。 |
| `signedOut` | 未登录 iCloud | 提示去系统设置登录，不做 App 登录。 |
| `disabled` | iCloud 不可用或权限关闭 | 本机继续可用，可重试检测。 |
| `syncing` | 正在同步 | 显示进度摘要和最近状态。 |
| `synced` | 已同步 | 显示上次成功时间。 |
| `failed` | 同步失败 | 保留 outbox，显示错误类别和重试入口。 |
| `accountChanged` | Apple ID 已变化 | 暂停同步，要求用户确认重新绑定/仅本机使用策略。 |
| `conflict` | 有冲突待处理 | 显示冲突数量，进入冲突处理。 |

入站和出站都必须幂等。正文、照片、标签关系和删除冲突不得静默 LWW 覆盖。

## Settings IA

设置页和详情页必须沿用 current 里的设置流与任务容器风格：`NavigationStack`、`TaskPageScrollView`、`TaskSurfaceSection`、`TaskSurfaceRow`、settings detail navigation chrome。不要为数据能力另起视觉体系。

```text
设置
  Pro 横幅

  内容管理
    心情统计
    标签管理
    垃圾箱

  数据
    iCloud 同步      >
    自动恢复点       >
    导出             >

  偏好
    面容解锁         [开关]
    语言             >
    外观主题         >

  关于
    关于心绪日记     >
    版本号
```

数据分组说明文案固定表达：

```text
所有时刻默认保存在本机，无需登录 App。后续登录 iCloud 后可在你的设备间同步。
```

### iCloud 同步详情页

- 说明本机保存默认可用、iCloud 只是系统同步。
- 显示当前状态、上次同步时间、待同步数量、失败类别、冲突数量。
- 提供手动重试。
- 未登录时提示“前往系统设置登录 iCloud”，不出现 App 登录表单。
- 不出现备份列表、恢复入口或导出入口。

### 自动恢复点详情页

- 说明“App 会自动保留最近 3 个本机恢复点，可查看并恢复，不能手动删除。”
- 显示最多 3 个恢复点列表，按时间倒序。
- 每项显示时间、记录数、照片数、App/schema version 和创建原因。
- 点恢复点进入恢复预览。
- 不提供删除、分享或导出恢复点入口。

### 恢复预览

- 只从自动恢复点详情页进入，不作为设置根页入口。
- 展示将恢复的恢复点、当前资料库摘要、替换范围和风险说明。
- 恢复按钮位于摘要之后，并使用危险操作样式和二次确认。
- 明确说明恢复失败不会破坏当前数据，恢复前会创建安全恢复点。
- 恢复准备成功后必须进入阻断式“等待重启完成恢复”状态，避免用户继续写入后被下次启动恢复覆盖。

### 导出详情页

- 提供 Markdown / PDF 格式选择。
- 提供范围选择：全部、当前主页筛选、日期范围；选择当前主页筛选时显示只读筛选摘要。
- 提供是否包含照片。
- 提供目标位置选择、进度、取消、失败重试和成功状态。
- 明确说明“导出会生成副本，不会改变当前数据，也不会影响 iCloud 同步。”

## Remaining Gaps

- SQLite/GRDB 依赖决策、首版 schema/repository 骨架、canonical runtime 类型、content-addressed asset store 和 SwiftData baseline 导入器已经进入 current；仍需要把导入器纳入受控 cutover，并补齐失败重试、rebuild 和恢复点协作策略。
- 需要把已落地的恢复点 retention=3、创建触发器和不可删除 UI 契约迁入 canonical recovery catalog，并补齐 asset pin。
- 需要在后续独立 iCloud 计划中，把当前 iCloud 三态启发式替换为可区分 Apple ID / 网络 / outbox / conflict 的状态模型。
- 需要在已落地的本地 canonical runtime/importer/asset store 上补齐 derived query layer、受控 cutover/rebuild path，并接入生产用户路径。
- 现有 SwiftData 过渡版恢复点只覆盖 `Moodments.store*`，不覆盖 `Application Support/Canonical/`；cutover 前必须定义 restore 后 canonical invalidation/rebuild 契约，或采用 wipe + reimport 作为唯一受控流程。
- 需要将已落地 SwiftData 过渡版恢复点迁入 canonical recovery catalog，并补齐 asset pin、restore job 表和 canonical replace cleanup。
- 需要实现 Markdown/PDF 导出服务和设置详情页流程。
- 需要另建 iCloud 独立计划，覆盖 custom zone 同步、outbox、checkpoint、冲突记录、用户可见状态和真机矩阵。

## Planned Work

### 0. 契约冻结

- 冻结目标依赖：canonical store 首选 GRDB；PDF 首选系统 renderer；外部 ZIP 备份文件后置。
- 冻结核心 schema：domain records、asset、mutation、sync、conflict、recovery、restore、export。
- 冻结自动恢复点策略：最多 3 个、按时间淘汰、不可删除、asset pin、创建触发器。
- 冻结设置 IA 和用户文案，明确本机保存、iCloud 同步、自动恢复点、导出四个概念。
- 记录 iCloud 后续计划边界状态草案：`localOnly / signedOut / disabled / syncing / synced / failed / accountChanged / conflict`，不作为 v1 关闭门槛。
- 冻结冲突矩阵：哪些可自动合并，哪些必须进入 `conflict_record`。

验收：计划和后续设计文档能让开发者直接区分 current、目标契约和未实现计划；没有把自动恢复点、外部备份文件和导出混为一谈；迁移前已有最小可用恢复点创建与校验契约。

### 1. Minimal Recovery Point Foundation

- 实现最小 `recovery_point` catalog、SQLite 快照载荷和 asset manifest。
- 实现迁移前恢复点创建，创建失败则中止 destructive migration。
- 实现恢复点完整性校验和不可恢复状态展示。
- 实现最多 3 个保留策略和 asset pin。
- 先提供内部 service 和测试，不必完成全部设置 UI。

验收：在任何 SwiftData -> canonical 迁移或 destructive schema migration 前，都能先创建一个可校验恢复点；连续创建第 4 个恢复点会淘汰最旧项；用户路径不存在删除入口。

### 2. Canonical Local Core

- 在已落地的本地 SQLite store、迁移框架、canonical write repository、runtime 类型和 SwiftData baseline 导入器上继续收敛。
- 建立受控 cutover：在切 UI 前执行 SwiftData -> canonical baseline 导入，导入必须携带 source fingerprint；restore 后必须 invalidation/rebuild 或 wipe + reimport，避免当前 SwiftData 恢复点 replace 后出现 stale canonical。
- 扩展 canonical schema、transaction boundary，并建立 derived query layer。
- 将首页、编辑、标签、垃圾箱、统计逐步迁到 repository/query layer。
- 保证未登录 iCloud、飞行模式、无网络时本地全功能可用。

验收：创建、编辑、标签、筛选、热力图、软删、恢复、彻底删除在 canonical store 下保持当前产品公理；迁移可重入，失败可重试，不破坏旧数据。

### 3. Asset Pipeline

- 已落地地基：SwiftData baseline 导入会将 Moment 原图写入 content-addressed asset 文件，并记录 hash、MIME、尺寸、字节数、创建时间和 moment-asset link。
- 已落地维护地基：`CanonicalAssetReachabilityService` 可审计 DB/文件系统 asset 一致性，并在无 blocking issue 且持有按 asset root 共享的 `CanonicalAssetOperationGate` 时清理 DB 无引用 orphan blob。
- 继续补齐 canonical UI 写入路径下的加图/删图/重排 asset 事务。
- 补齐 asset pin：recovery point、restore staging、export job 和后续 sync pin 不能混入引用计数；因为多个 `asset_record.id` 可以共享同一个 `content_hash` blob，liveness 必须按 `content_hash` 聚合或使用独立 pin 表，不能直接把 record-level `pin_count` 当最终 GC 依据。
- 缩略图继续作为可丢弃缓存。
- 继续实现 DB orphan `asset_record` finalizer 和完整 asset GC。
- 完整 GC 必须尊重 recovery point、restore staging、export job 和 sync pin；当前 orphan blob cleanup 只能处理 DB 无引用文件，不能替代完整 GC。后续所有 canonical UI asset 写入必须复用同一 asset root 的 operation gate；如果引入跨进程后台任务，则升级为持久 staging/pin 方案，不能出现“blob 已落盘但 DB metadata 未提交”期间被 cleanup 误删的窗口。

验收：加图、删图、恢复、彻底删除、恢复点保留和导出期间都不会误删资产；baseline import 已能证明 asset metadata 与 content-addressed 文件字节一致，reachability audit 已能发现 missing/corrupt/orphan/unlinked 状态，但该阶段还不能关闭，直到 pin、DB record finalizer 和完整 GC 完成。

### 4. Recovery Point UI And Restore

- 将 SwiftData 过渡版恢复点能力迁入 canonical `recovery_point` catalog。
- 在 canonical store 下重新实现最多 3 个保留策略、asset pin、恢复点淘汰和资产 GC 协作。
- 在 destructive schema migration 前创建可校验恢复点。
- 在 canonical replace restore 后重建 `syncEpoch` 占位、清空旧 outbox/token 占位、重建 projection。
- 保持已落地用户契约：设置页最多 3 个恢复点、可恢复、不可删除；准备恢复后阻断继续使用；恢复失败不破坏当前 library。

验收：用户可看到最多 3 个恢复点并恢复；用户不能删除恢复点；连续创建第 4 个恢复点会淘汰最旧项；准备恢复后不能继续写入；恢复失败不破坏当前 library。

### 5. Export

- 实现 Markdown 导出：稳定文件名、相对图片链接、范围筛选。
- 实现 PDF 导出：分页、图片嵌入、长文排版。
- 实现导出详情页：格式、范围、照片选项、目标位置、进度、取消、失败重试。
- 如果选择“当前主页筛选”，详情页必须显示只读筛选摘要，避免设置任务空间里的“当前”产生歧义。
- 导出任务从一致性快照读取，不阻塞 UI，不改变 canonical store。

验收：导出成功、取消、失败、重试、目标冲突和临时文件清理都有可测行为；导出文件不是备份，也不参与 iCloud。

### 6. iCloud Sync Follow-up Plan

- 本计划不把 iCloud 作为 v1 关闭门槛。
- 本地 canonical、恢复点和导出验收通过后，单独建立 iCloud sync plan。
- 后续计划再冻结 CloudKit custom zone、record mapper、`sync_outbox`、`sync_checkpoint`、Apple ID 变化、冲突 UI 和真机矩阵。

验收：已创建独立 iCloud plan，且不会改变 v1 本地权威、恢复点和导出的已验收语义。

### 7. Cleanup And Hardening

- 移除 SwiftData 作为生产权威的残留路径，保留必要迁移历史。
- 更新 `docs/current/` 为最终 as-built 真相，计划层只保留未完成项。
- 更新隐私文案、Privacy Manifest 注释和用户可见错误文案。
- 补齐快照/视觉验证，确保新增设置页和详情页沿用现有任务容器风格。
- 全量 `./scripts/verify.sh` 通过；iCloud 真机证据进入独立 iCloud plan。

## Verification Matrix

阶段内验证采用风险分层：实现小步优先运行相关单元测试、窄 UI 测试、`build`、`lint` 和 `diff-check`；不要求每个功能点都跑全量 `./scripts/verify.sh`。阶段收口、跨 UI 主流程、发布前或修改共享基础设施时再跑全量 `verify.sh`。这样保留可验证性，同时避免每次局部实现都被长时间 UI 全量回归阻塞。

| 范围 | 必测内容 |
| --- | --- |
| Canonical store | schema migration、启动 runtime、事务回滚、幂等写入、baseline 导入不写 mutation/tombstone、projection rebuild、SwiftData cutover 重入。 |
| 删除生命周期 | `active / softDeleted / purgePending / purged`、垃圾箱、旧设备离线编辑不可复活 purged 记录。 |
| Asset pipeline | hash、引用、pin、GC、恢复点/导出/staging 期间不误删。 |
| 自动恢复点 | 最多 3 个、按时间淘汰、不可删除、列表可见、恢复预览、恢复失败不破坏现库。 |
| Restore | staging 校验、atomic replace、崩溃中断、`syncEpoch` 重建、旧 outbox/token 作废。 |
| Export | Markdown 相对链接、PDF 分页、取消、失败重试、目标冲突、临时文件清理。 |
| Settings IA | 独立数据分组、iCloud/自动恢复点/导出详情页、面容解锁根页开关、无 App 登录入口。 |
| iCloud follow-up | 独立计划覆盖未登录、关闭 iCloud、单设备、两设备、Apple ID 变化、离线后恢复、图片同步、删除传播、冲突记录。 |

## Acceptance

计划可以关闭的条件：

- current 文档明确写入最终 as-built 数据生命周期，并移除“SwiftData 是目标权威”的任何暗示。
- 任一用户记录从创建到编辑、软删除、恢复、彻底删除、自动恢复点、从恢复点恢复、Markdown 导出、PDF 导出都有可追踪状态和测试证据。
- 设置页让用户清楚区分本机保存、iCloud 同步、自动恢复点和导出；不出现 App 登录入口；不把 iCloud 写成云端备份。
- App 被杀、弱网、重复同步、CloudKit 暂不可用、Apple ID 变化、资产缺失、恢复点损坏、导出失败时都有确定行为，不靠内存状态或静默吞错。
- 自动恢复点最多 3 个、用户不可删除、可查看并恢复；恢复前创建安全恢复点，恢复失败不破坏现有 library。
- Markdown/PDF 导出只读、可取消、失败可重试，不改变 canonical store。
- iCloud 已拆为独立后续计划，且该计划不改变本计划已验收的本地权威、自动恢复点和导出语义。
