# Moodments 数据生命周期实现计划

本文是当前主动计划，只记录尚未完成的目标架构、实施顺序和验收条件。已落地事实进入 [`../current/`](../current/README.md)；产品语义以 [`../product-mental-model.md`](../product-mental-model.md) 为准。

当前仓库没有单独的 `docs/design/` 目录，因此本文临时承载两类非 current 内容：前半部分的目标契约（target contract）和后半部分的主动计划（active plan）。任一内容落地验收后，as-built 真相必须迁入 `docs/current/`，本文只保留仍未完成的计划或最终关闭证据。

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

- 当前 App 仍保留 SwiftData `Moment` / `Tag` / `MomentImage` 模型和 `ModelContainer`，但 M4 后它们只承担 baseline 导入、过渡恢复代码和部分测试种子；主 UI、用户写入、用户可触达恢复点和 Markdown/PDF 导出不再把 SwiftData 作为读写权威。
- 当前生产启动路径会先消费 canonical pending restore，再创建 SwiftData 过渡容器、`CanonicalLibraryRuntime`、`CanonicalLibraryService` 和 `CanonicalRecoveryCoordinator`；`RootView` 进入主页前执行 SwiftData -> canonical baseline 导入，若本次启动刚完成 canonical restore 则跳过 baseline 导入。
- 当前 `SyncStatusService` 只是启发式状态展示：`cloudKitEnabled + 网络可达性 + 最近本地写入时间`，不是 CloudKit import/export 事件，也不表达未登录 iCloud、账号变化、冲突、失败重试或恢复进度；M3 后也不代表 canonical iCloud 同步已经完成。
- 当前 UI 用户写入入口 `LocalLibraryMutationService` 已支持 canonical production backend 和 SwiftData transition backend；主流程创建/编辑/删除/恢复/彻底删除时刻以及标签 CRUD 已走 canonical repository，普通写入稳定恢复点和高风险安全点已切到 `CanonicalRecoveryCoordinator`。
- 当前已有 SwiftData 过渡版本机自动恢复点代码和测试，但 M3 后它不再是生产恢复路径；设置页“备份与恢复”生产入口已接 `CanonicalBackupRestoreService`，恢复点列表/预览、prepare restore、阻断页和下次启动 replace restore 都走 canonical recovery catalog / snapshot / boot restore gate。
- 当前已有 GRDB canonical store、M1 repository parity、M2 main UI runtime cutover、M3 recovery cutover、M4 export cutover、`CanonicalLibraryRuntime` 装配类型、SwiftData -> canonical baseline 导入器测试，以及 canonical recovery point catalog / asset manifest / recoveryPoint pin / 真实 SQLite snapshot 创建与校验 / restore executor / boot restore gate / migration safety gate 测试。
- 当前尚未完成完整数据生命周期：无持久 outbox、无自定义同步状态机、无真实 iCloud 多设备验收；SwiftData production wiring 仍需在 M5 退役。
- 当前 SwiftData 是过渡来源和待退役支撑路径，不作为目标架构里的最终数据权威。

## M0 Canonical Cutover Contract

M0 的目标不是继续扩功能，而是把生产切换的单一权威边界、影响面和退出标准固定下来。项目尚未上线，因此不做旧 SwiftData 方案的长期兼容、迁移矩阵或双写。

### M0 决策

- 生产目标固定为 `Canonical Repository + GRDB + SQLite + FileAssetStore`；SwiftData 只保留为 current 事实和受控 cutover 前的过渡来源。
- 验收通过后的生产启动不得再创建 SwiftData `ModelContainer`，不得把 SwiftData 作为 UI 读写、恢复点或导出的运行期数据源。
- 不做 SwiftData + GRDB 双写。任何双权威都会让恢复点、导出、图片 GC 和后续 iCloud 同步出现不可解释的竞态。
- 因 App 未上线，cutover 采用破坏式切换：验收通过后删除或隔离 SwiftData 生产路径；不保留用户可见的“旧存储模式”。
- cutover 后恢复只走 canonical recovery catalog / snapshot / boot restore gate。SwiftData 过渡恢复点路径随生产切换退役，不能继续承担恢复一致性。
- M0 不把 iCloud、CloudKit outbox/checkpoint、冲突 UI、外部备份包、导出范围选择、持久 `export_job` 或完整后台 GC 作为关闭条件。

### 目标生产路径

```text
MoodmentsApp
  -> CanonicalBootRestoreGate
  -> CanonicalLibraryRuntime
      -> CanonicalLibraryRepository
      -> FileAssetStore
      -> CanonicalRecoveryCoordinator
      -> CanonicalBackupRestoreService
      -> ExportService(canonical snapshot source)
  -> SwiftUI feature models / views
```

启动顺序必须是阻断式、可解释的：先消费 pending restore，再打开 canonical runtime；如果发生受控 cutover，则在用户进入主时间轴前完成导入/校验/切换，不能让 UI 先使用 SwiftData 再后台悄悄切库。

### 影响面清单

| 面 | 当前事实 | cutover 前缺口 | 目标 |
| --- | --- | --- | --- |
| App 启动 | `MoodmentsApp` 已在创建 `CanonicalLibraryRuntime` 前调用 canonical boot restore gate；仍会创建 SwiftData 过渡容器用于 baseline 导入和测试种子。 | M5 退役生产 SwiftData 容器。 | 生产启动只打开 canonical runtime。 |
| 用户写入 | `LocalLibraryMutationService` 主流程 backend 已调用 canonical repository；稳定恢复点/高风险安全点已切到 canonical recovery coordinator；SwiftData backend 仅过渡保留。 | M5 删除或隔离 SwiftData transition backend 的生产 wiring。 | UI 不知道底层 store，写入只进 canonical transaction。 |
| 时间轴/筛选 | `TimelineHomeView`、`TimelineViewportView`、`FilterPanelView` 已通过 canonical service 读取时间轴和标签。 | 剩余为 UI 测试种子从 SwiftData 过渡到 canonical。 | 时间轴和筛选不依赖 SwiftData model。 |
| 预览/编辑 | `MomentPreviewView`、`MomentEditorModel` 已消费 canonical 预览/编辑 payload 和原图读取。 | 剩余为 M5 清理 SwiftData 过渡辅助。 | 预览和编辑只消费值类型。 |
| 标签管理 | `TagManageView` / `TagPickerView` 已通过 canonical service 列表和 mutation service 写入。 | 剩余为 UI 测试种子和最终 SwiftData 退役。 | 标签入口统一走 canonical service。 |
| 垃圾箱 | `TrashView` 已从 canonical 读取垃圾箱并通过 canonical backend 恢复/彻底删除；高风险恢复/彻底删除前会创建 canonical mutation safety 恢复点。 | M5 清理 SwiftData 过渡测试辅助。 | 删除生命周期完全由 canonical 状态机表达。 |
| 统计/热力图 | `MoodStatsModel`、`YearHeatmapModel` 已通过 canonical 聚合查询。 | 剩余为最终 SwiftData aggregation 测试辅助退役。 | 统计、热力图与时间轴同源。 |
| 图片/缩略图 | 主 UI 原图读取、编辑写入和导出图片读取已走 `FileAssetStore`；旧 SwiftData image data 仅作过渡来源。 | M5 清理旧路径。 | 原图由 `FileAssetStore` 管理，SQLite 只存 metadata/link。 |
| 自动恢复点 | 设置页“备份与恢复”已使用 `CanonicalBackupRestoreService`，启动结果消费 canonical boot result，恢复点列表/预览/恢复全走 canonical。 | M5 删除或隔离旧 SwiftData `LocalBackupCoordinator` / `LocalBackupRestoreExecutor` 的生产 wiring。 | 恢复点列表/预览/恢复全走 canonical。 |
| 导出 | `ExportView` 生产路径通过 `CanonicalExportSnapshotStore` 从 canonical repository / `FileAssetStore` 读取，复用 Markdown/PDF renderer；SwiftData export snapshot store 仅作为过渡代码残留。 | M5 删除或隔离 SwiftData 过渡导出代码。 | 导出与 UI 读写同源，不改变 canonical store。 |
| 测试数据 | 多数 UI seed 和单测 fixture 仍构造 SwiftData `ModelContext`。 | 提供 canonical test runtime / seed helper，重写主流程测试入口。 | 验证生产路径而不是旧过渡路径。 |

### 分阶段切换

1. **M1 Repository parity（已落地，见 current）**：canonical read/write facade 已覆盖创建、编辑、软删除、恢复、彻底删除、标签 CRUD、时间轴筛选、预览详情、编辑 payload、图片读写、统计/热力图聚合和额度计数。
2. **M2 Main UI runtime cutover（已落地，见 current）**：`MoodmentsApp`、`RootView` 和主流程 feature models 已切到 canonical runtime；时间轴、编辑、预览、标签、垃圾箱、统计/热力图里的 `@Query` / `ModelContainer` 依赖已移除或退到 SwiftData 过渡测试路径。恢复点生产切源已在 M3 完成，导出生产切源已在 M4 完成。
3. **M3 Recovery cutover（已落地，见 current）**：设置页“自动恢复点/备份与恢复”已切到 `CanonicalBackupRestoreService`；写入触发器已切到 `CanonicalRecoveryCoordinator`；启动期已消费 canonical pending restore；SwiftData 恢复路径退出生产。
4. **M4 Export cutover（已落地，见 current）**：Markdown / PDF 已改读 canonical snapshot source；图片从 `FileAssetStore` 读取；导出仍是只读副本，范围选择和持久 job 后置。
5. **M5 SwiftData production removal**：在 M2-M4 全部验收后，删除或隔离 SwiftData production wiring、过渡恢复 coordinator、过渡导出 snapshot store 和 UI seed 对 SwiftData 的依赖；此阶段完成后才允许宣称 SwiftData 只剩受控导入工具或历史测试辅助。更新 current 文档为 canonical as-built。

### M0 Acceptance

- 本计划明确 current、目标和未实现计划：current 主 UI、恢复和导出已切 canonical，SwiftData 仍是导入和测试种子的过渡支撑，目标生产是 canonical 全链路。
- 后续实现的退出标准明确为“M5 验收后生产路径不再创建 SwiftData `ModelContainer`，UI/恢复/导出不再读写 SwiftData”。
- 已列出所有必须脱离 SwiftData 的生产入口：启动、写入、时间轴、筛选、预览、编辑、标签、垃圾箱、统计/热力图、图片、恢复点、导出、测试种子。
- 恢复一致性收敛为单一路径：cutover 后只走 canonical recovery；不保留“SwiftData restore 后 rebuild canonical”的并行生产策略。
- 设置页仍保持 iCloud 同步、自动恢复点、导出三入口分离；恢复预览只从自动恢复点进入；导出切源到 canonical snapshot 后仍只表达只读副本。
- iCloud、外部备份包、导出范围选择、持久 `export_job`、完整后台 GC 和多设备冲突不进入 M0 关闭条件。

## Mature Choices

| 需求 | 采用方案 | 边界 |
| --- | --- | --- |
| 本地权威、事务、迁移、查询 | SQLite + GRDB | 已冻结为生产目标；后续不再回到 SwiftData repository 作为权威。 |
| 图片与大文件 | Content-addressed file asset store | 文件归 App 管理；SQLite 只存 metadata、hash、引用和 pin。 |
| 崩溃后恢复 | SQLite transaction + durable job tables | 写入、恢复、导出、同步都用持久状态；不靠内存队列。 |
| 本机自动恢复点 | Recovery point catalog + atomic snapshot/replace | v1 最多 3 个恢复点；用户不可删除。 |
| PDF 导出 | 系统 PDF renderer | 优先用 Apple 系统能力，不引入重型排版框架。 |
| Markdown 导出 | 自有轻量 renderer | 从一致性快照生成文本和相对图片目录。 |
| iCloud 同步 | CloudKit private database + single custom zone | 后续独立计划；只做个人多设备同步，不做协同平台。 |
| 外部备份文件 | 后续可选 ZIP package | 只有明确要分享/迁移备份文件时才引入 ZIP 依赖，避免 v1 范围膨胀。 |

## Core Data Model

下表是目标数据生命周期的对象地图，不等于 M0 必须一次实现的 schema。M0 只冻结本地生产 cutover 的最小闭环：`library_metadata`、Moment/Tag/link、asset metadata、mutation/tombstone、recovery point catalog 和 restore staging。`sync_*`、`conflict_record`、`export_job` 属于后续 iCloud / 导出增强计划，不能阻塞本地 canonical 切生产。

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
| `conflict_record` | 后续 iCloud 计划使用的用户可见冲突记录；M0 不引入冲突 UI，也不把该表作为本地切生产关闭条件。 |
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

- SQLite/GRDB 依赖决策、首版 schema/repository 骨架、canonical runtime 类型、content-addressed asset store、SwiftData baseline 导入器、M2 主 UI runtime cutover、M3 recovery cutover 和 M4 export cutover 已经进入 current；仍需要把最终 SwiftData 退役收口。
- 已将 canonical recovery catalog、asset manifest、retention=3、recoveryPoint content-hash pin、真实 SQLite snapshot 创建、snapshot/asset 校验、recovery coordinator、stage/arm/boot replace/rollback restore executor、restoreStaging pin、boot restore gate、migration safety gate、生产恢复触发器、生产启动 gate 和用户可见 canonical 恢复点路径接到 canonical。
- 需要在后续独立 iCloud 计划中，把当前 iCloud 三态启发式替换为可区分 Apple ID / 网络 / outbox / conflict 的状态模型。
- canonical repository parity、主 UI runtime/query layer cutover、recovery cutover 和 export cutover 已落地并进入 current；剩余生产切源集中在最终 SwiftData 移除。
- 旧 SwiftData 过渡版恢复点只覆盖 `Moodments.store*`，不覆盖 `Application Support/Canonical/`；M3 后它不再作为生产恢复路径，后续 M5 只需要删除或隔离旧 production wiring。
- 恢复点触发器、生产恢复执行、设置页恢复点 UI 和普通生产启动 gate 已接入 canonical。当前仍没有持久 `restore_job` 表；这不是 M4 导出闭环前置条件，如需补齐应作为后续恢复增强计划单独评估。
- Markdown / PDF 导出已完成 canonical source cutover；范围选择、取消/失败重试、持久 `export_job` 和 canonical export pin 属于后续增强，不是 M5 前置条件。
- 需要另建 iCloud 独立计划，覆盖 custom zone 同步、outbox、checkpoint、冲突记录、用户可见状态和真机矩阵。

## Planned Work

### 0. M0 Canonical Cutover Contract

- 已冻结生产目标：`Canonical Repository + GRDB + SQLite + FileAssetStore`，SwiftData 不再作为目标权威。
- 已冻结切换原则：不双写、不长期兼容旧方案、不保留用户可见旧存储模式；验收后 SwiftData 退出生产启动、UI 读写、恢复点和导出路径。
- 已冻结单一恢复策略：cutover 后只走 canonical recovery catalog / snapshot / boot restore gate；SwiftData 过渡恢复路径随生产切换退役。
- 已列出 cutover 影响面：启动、写入、时间轴、筛选、预览、编辑、标签、垃圾箱、统计/热力图、图片、自动恢复点、导出和测试种子。
- 已明确 M0 非目标：iCloud/CloudKit、`sync_outbox` / checkpoint、冲突 UI、外部备份包、导出范围选择、持久 `export_job`、完整后台 GC 和多设备验收。
- 已保留设置 IA 边界：本机保存、iCloud 同步、自动恢复点、导出继续拆开表达，用户无需 App 登录。

验收：本节能直接指导后续 M1-M5 实现；开发者可以判断一个入口是否仍错误依赖 SwiftData；用户侧不会把自动恢复点、外部备份文件、Markdown/PDF 导出和 iCloud 同步混为一谈；M0 不宣称代码已经切换。

### 1. Minimal Recovery Point Foundation

- 已落地内部 `recovery_point` catalog 与 asset manifest：v4 `recovery_point_record` / `recovery_point_asset_record` 记录 SQLite snapshot 相对路径/字节数/hash、schema/app version、source library、原因、状态和记录/标签/照片计数。
- 已落地内部最多 3 个保留策略和 recoveryPoint asset pin：正常创建恢复点或显式执行 retention 时，会在单个 GRDB 写事务内按 `createdAt DESC, id DESC` 保留 3 个并释放被淘汰项的 pin；prepare restore 为避免 arm 失败丢失 selected snapshot，允许 restore safety 在 arm 前暂缓 retention。
- 已落地真实 SQLite snapshot 创建与校验：使用 GRDB online backup 写入 staging，从 snapshot 自身读取 metadata/count/asset manifest，校验 asset blob，atomic move 后写 catalog；snapshot hash / byte count / schema version / asset blob 校验失败会把 catalog status 标为 `invalid`；第 4 个恢复点会同步删除被淘汰的 snapshot 目录。
- 已落地内部 canonical restore executor：stage 时复制 selected snapshot 到 `PendingRestore/payload`、写 pending context、用 `restoreStaging` content-hash pin 保护 asset；arm 后启动期 replace，成功前重写 staged SQLite 的当前本机 `libraryID` / `deviceID` 和新 `syncEpoch`，非 critical 失败会 rollback 并清理 pending；unarmed pending 不替换当前 store；pending context 缺失或损坏时会释放 staging pin，复制新库失败后会 rollback 保留当前 store。
- 已落地内部 canonical recovery coordinator：提供恢复点列表、当前 counts、稳定变更节流恢复点、mutation safety 恢复点、恢复点校验、兼容性检查和 prepare restore；prepare restore 先 stage selected，再创建暂缓 retention 的 restore safety，arm 成功后才执行 retention，避免 arm 失败时丢失 selected snapshot；arm 后 retention 失败会作为返回状态暴露，pending restore 仍视为已准备。
- 已落地内部 canonical boot restore gate：调用方可在打开 `CanonicalLibraryRuntime` 前先消费 pending restore；无 pending 时不创建 canonical root / DB；armed pending 成功替换后再由调用方打开 runtime；unarmed pending 会清理且不替换；损坏 armed pending 返回 failure 并保留当前 store；rollback 失败仍作为 critical error 抛出，避免继续打开半替换 store。
- 已落地内部迁移前恢复点闸门：destructive migration / cutover 调用方可要求先创建并校验 `.schemaMigration` 恢复点，创建或校验失败则中止。
- 已落地恢复点不可恢复状态的 UI value model 和禁用展示；生产 SwiftData 适配器与 canonical 适配器都映射到同一 `BackupRestoreServicing` 协议。
- 生产触发器和设置 UI 已复用同一 service 与 UI 协议接入 canonical，没有另建同职责备份协调器。

验收：在任何 SwiftData -> canonical 迁移或 destructive schema migration 前，都能先创建一个可校验恢复点；正常完成 create/enforce retention 后，连续创建第 4 个恢复点会淘汰最旧项并释放对应 pin；coordinator 能证明稳定变更节流、安全点、兼容性拒绝、prepare restore 组合顺序和 arm 后 retention 失败语义；restore executor 能证明 armed restore 可替换、unarmed 不替换、失败不破坏当前 store、restoreStaging pin 可清理；boot gate 能证明 runtime 打开前可消费 pending restore，且 no-pending 不物化 canonical store；用户路径不存在删除入口。当前 catalog / manifest / pin / retention / 真实 snapshot 创建与校验 / coordinator / restore executor / boot gate / migration safety gate / UI 服务边界 / 普通 SwiftUI 生产启动 / 用户可见 canonical 恢复点路径已有测试证据。

### 2. Canonical Local Core And UI Cutover

- 已落地 M1 repository parity：创建、编辑、软删除、恢复、彻底删除、标签 CRUD、时间轴筛选、预览详情、编辑 payload、图片读写、统计/热力图聚合和额度计数已有 canonical repository 能力和定向测试。
- 已落地 M2 主 UI runtime cutover：`MoodmentsApp` / `RootView` 注入 `CanonicalLibraryService`，进入主页前执行 SwiftData -> canonical baseline 导入；首页、编辑、预览、标签、垃圾箱、统计、热力图已迁到 canonical service / repository。
- 已复用 canonical transaction boundary 和等价查询 facade；没有新增过重 projection。
- 当前 `.modelContainer(container)` 仍保留给 SwiftData baseline import 和 seed；不再作为主 UI、恢复或导出权威。
- 设置页“备份与恢复”入口已在 M3 重新开放，并接到 canonical `BackupRestoreServicing`。
- 后续不再把主 UI cutover、recovery cutover 和 export cutover 作为计划重复实现，只处理 M5 SwiftData production removal 中暴露的必要尾项。

验收：创建、编辑、标签、筛选、预览、热力图、统计、软删、恢复、彻底删除在 canonical store 下保持当前产品公理；生产 UI 不再使用 `@Query` / SwiftData model；cutover 失败不进入可写的混合状态。生产启动不再创建 SwiftData `ModelContainer` 的最终退出条件移到 M5，在恢复和导出切源后执行。

### 3. Asset Pipeline

- 已落地地基：SwiftData baseline 导入会将 Moment 原图写入 content-addressed asset 文件，并记录 hash、MIME、尺寸、字节数、创建时间和 moment-asset link。
- 已落地维护地基：`CanonicalAssetReachabilityService` 可审计 DB/文件系统 asset 一致性，并在无 blocking issue 且持有按 asset root 共享的 `CanonicalAssetOperationGate` 时清理 DB 无引用 orphan blob。
- 已落地 GC 计划地基：`planGarbageCollection()` 可 dry-run 列出 finalizable `asset_record`、当前 orphan blob、finalize 后才可删的 blob；`finalizeUnlinkedAssetRecords()` 只删除 DB 中无 link 且 `pin_count == 0` 的 asset record，并在执行时重查 DB，整批条件不一致时不提交部分删除。
- 已落地 content-hash pin 地基：v3 `asset_pin_record` 使用 `content_hash + owner_kind + owner_id` 表达 recovery/export/sync 等 owner 的 lease；`CanonicalAssetPinStore` 支持 upsert pin / release；pin-aware planner 不会把 active pin 保护的 blob 放入 removable 列表。
- 继续补齐 canonical UI 写入路径下的加图/删图/重排 asset 事务。
- recovery point 和内部 restore staging 已接入 `asset_pin_record` 的创建 / 释放；继续把 export job 和后续 sync job 接入真实 pin 生命周期。它们不能混入引用计数，不能直接把 record-level `pin_count` 当最终 GC 依据。
- 缩略图继续作为可丢弃缓存。
- 继续实现完整 asset GC 的执行入口和 recovery/export/sync pin 生命周期集成。
- 完整 GC 必须尊重 recovery point、restore staging、export job 和 sync pin；当前 DB orphan finalizer + orphan blob cleanup 仍不能替代完整 GC。后续所有 canonical UI asset 写入必须复用同一 asset root 的 operation gate；如果引入跨进程后台任务，则升级为持久 staging/pin 方案，不能出现“blob 已落盘但 DB metadata 未提交”期间被 cleanup 误删的窗口。

验收：加图、删图、恢复、彻底删除、恢复点保留和导出期间都不会误删资产；baseline import 已能证明 asset metadata 与 content-addressed 文件字节一致，reachability audit 已能发现 missing/corrupt/orphan/unlinked/negative pin/invalid content pin 状态，GC dry-run、content-hash pin planner 与 DB orphan finalizer 已覆盖普通 DB orphan 记录和 active pin 保护边界，但该阶段还不能关闭，直到 recovery/export/sync pin 生命周期和完整 GC 执行入口完成。

### 4. Recovery Point UI And Restore

已关闭，as-built 真相见 `docs/current/`：

- SwiftData 过渡版恢复点触发器、设置列表/预览和用户触发的恢复执行已迁入 canonical `recovery_point` catalog。
- 设置页生产入口使用 `CanonicalBackupRestoreService`，最多展示 3 个系统维护恢复点，用户可进入恢复预览并准备恢复，不能删除恢复点。
- canonical 写入触发器已接 `CanonicalRecoveryCoordinator`：普通写入成功后异步创建稳定恢复点，高风险操作前创建 mutation safety 恢复点且失败时中止。
- 设置页准备恢复后写 pending/armed，上层进入阻断页；普通生产启动在打开 `CanonicalLibraryRuntime` 前调用 `CanonicalBootRestoreGate` 消费 pending restore。
- prepare restore 创建 restore safety 后会更新 staged context；boot replace 时把 restore safety catalog 注入 incoming snapshot，恢复完成后安全点仍在恢复点列表中。
- SwiftData 过渡版 `LocalBackupCoordinator` / `LocalBackupRestoreExecutor` 不再作为生产恢复路径；只可保留为 M5 删除前的历史测试或受控迁移辅助。

验收证据：`BackupRestoreServiceTests`、`LocalLibraryMutationServiceTests`、`CanonicalRecoveryCoordinatorTests`、`CanonicalRestoreExecutorTests`、`CanonicalBootRestoreGateTests`、`BackupRestoreUITests/testBackupListShowsSystemMaintainedRecoveryPointAndPreview`、`BackupRestoreUITests/testPreparedRestoreRunsOnNextLaunchAndShowsSuccess`。

### 5. Export

- Markdown / PDF 导出 M1 已落地：设置详情页可导出全部活跃 Moment，稳定文件名、Markdown 文档、相对图片链接、PDF 分页和图片嵌入已覆盖；范围筛选仍未实现。
- 先把导出数据源从 SwiftData snapshot 切到 canonical snapshot：active moments、tag names、asset links 和原图 bytes 都从 canonical store / `FileAssetStore` 读取。
- 补齐 Markdown 范围选择：全部、当前主页筛选、日期范围。
- 补齐导出详情页：范围、照片选项、目标位置、进度、取消、失败重试。
- 如果选择“当前主页筛选”，详情页必须显示只读筛选摘要，避免设置任务空间里的“当前”产生歧义。
- 导出任务从一致性快照读取，不阻塞 UI，不改变 canonical store。

验收：Markdown / PDF 导出不再读取 SwiftData；导出成功、取消、失败、重试、目标冲突和临时文件清理都有可测行为；导出文件不是备份，也不参与 iCloud。

### 6. iCloud Sync Follow-up Plan

- 本计划不把 iCloud 作为 v1 关闭门槛。
- 本地 canonical、恢复点和导出验收通过后，单独建立 iCloud sync plan。
- 后续计划再冻结 CloudKit custom zone、record mapper、`sync_outbox`、`sync_checkpoint`、Apple ID 变化、冲突 UI 和真机矩阵。

验收：已创建独立 iCloud plan，且不会改变 v1 本地权威、恢复点和导出的已验收语义。

### 7. Cleanup And Hardening

- 删除或隔离 SwiftData 生产 wiring 的残留引用，保留必要迁移历史和已明确的测试辅助。
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

## Final Plan Acceptance

本节是整份数据生命周期 implementation plan 的最终关闭条件，不是 M0 contract 的关闭条件。M0 的验收只看 `M0 Canonical Cutover Contract` 小节。

计划可以关闭的条件：

- current 文档明确写入最终 as-built 数据生命周期，并移除“SwiftData 是目标权威”的任何暗示。
- 任一用户记录从创建到编辑、软删除、恢复、彻底删除、自动恢复点、从恢复点恢复、Markdown 导出、PDF 导出都有可追踪状态和测试证据。
- 设置页让用户清楚区分本机保存、iCloud 同步、自动恢复点和导出；不出现 App 登录入口；不把 iCloud 写成云端备份。
- App 被杀、弱网、重复同步、CloudKit 暂不可用、Apple ID 变化、资产缺失、恢复点损坏、导出失败时都有确定行为，不靠内存状态或静默吞错。
- 自动恢复点最多 3 个、用户不可删除、可查看并恢复；恢复前创建安全恢复点，恢复失败不破坏现有 library。
- Markdown/PDF 导出只读；M1 已做到成功/失败可测且不改变当前 store，后续仍需补齐取消、失败重试和 canonical `export_job` 闭环。
- iCloud 已拆为独立后续计划，且该计划不改变本计划已验收的本地权威、自动恢复点和导出语义。
