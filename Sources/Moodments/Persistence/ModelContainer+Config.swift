import Foundation
import SwiftData
import os

/// `ModelContainer` 装配。见 `docs/design/07-data-persistence.md` §1（SwiftData 选型）与
/// `docs/design/08-architecture.md` §0（持久化：SwiftData + CloudKit 私有库）。
enum ModelContainerConfig {
    /// 全部 `@Model` 类型的 schema，供本地与 CloudKit 两种配置共用。
    static var schema: Schema {
        Schema([Moment.self, Tag.self, MomentImage.self])
    }

    /// 本地持久化配置（阶段 1–6 使用）：落盘、不接入 CloudKit。
    /// 阶段 7 接入 entitlements 后可切换到 `makeCloudKitContainer()`。
    static func makeLocalContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// 纯内存容器：供单元测试与 SwiftUI 预览使用，不落盘、不需要签名/entitlements，
    /// 保证阶段 1 的构建与测试不依赖 iCloud 能力。
    static func makeInMemoryContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// 落盘到指定 `url` 的容器：供单元测试验证真实磁盘往返行为（如软删除字段跨
    /// `ModelContainer` 实例重新读取仍保持正确值），调用方负责创建/清理该目录。
    static func makeContainer(at url: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(schema: schema, url: url)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    // MARK: - CloudKit 私有库配置（阶段 7）

    /// CloudKit 私有库容器标识符，与 `Config/Moodments.entitlements`
    /// 的 `com.apple.developer.icloud-container-identifiers` 声明一致（见 09-icloud-sync.md §9.1）。
    static let cloudKitContainerIdentifier = "iCloud.com.moodments.app"

    /// CloudKit 容器专用的磁盘文件路径，**刻意与 `makeLocalContainer()` 的默认路径不同**
    /// （阶段7实测登记）：二者若共用同一默认文件，一次失败/中断的 CloudKit 初始化尝试可能已
    /// 在磁盘上留下按 CloudKit schema 校验过的文件状态，导致其后 `makeLocalContainer()`
    /// 打开**同一份文件**时被拖累一并失败——已实测复现（无 entitlements 环境下两者共用
    /// 默认路径时，`makeProductionContainer()` 的本地回退分支也会抛出同样的
    /// 「CloudKit integration requires relationships be optional」错误并触发
    /// `fatalError`）。二者使用不同文件从根本上消除这种跨路径污染的可能。
    private static var cloudKitStoreURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MoodmentsCloudKit.store")
    }

    /// 启用 CloudKit 同步的容器（`Moment`/`Tag`/`MomentImage` 参与同步，见 07 §2、09 §9.1）：
    /// `AppearancePreference`/`SubscriptionStateCache` 不接入 CloudKit（各自本地 `UserDefaults`
    /// 承载，见 07 §6/§7），故本容器 schema 与 `makeLocalContainer()` 完全一致，只多声明
    /// `cloudKitDatabase` + 使用独立磁盘路径（见 `cloudKitStoreURL`）。
    /// - Throws: 缺少 iCloud entitlements/未签名/未登录 iCloud 等场景下，`ModelContainer` 初始化
    ///   可能抛出——调用方（`makeProductionContainer()`）负责回退，本方法自身不做兜底。
    static func makeCloudKitContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            schema: schema,
            url: cloudKitStoreURL,
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    /// 进程自身是否具备可用的 iCloud 能力（阶段7验证中新增、**必须在触碰任何 CloudKit API
    /// 之前**调用的门槛判断）：用公开 API `FileManager.ubiquityIdentityToken` 探测——该属性
    /// 是 Apple 专为「在不触发 CloudKit/文档同步初始化的前提下探测 iCloud 可用性」设计的公开
    /// 接口，本身不属于 CloudKit API，缺少 entitlements/未登录 iCloud 时只会返回 `nil`，
    /// 不会崩溃。
    ///
    /// **为什么不能只靠 `try`/`catch`（关键实测结论）**：完全未签名的进程（本仓库
    /// `scripts/build.sh`/`test.sh` 用 `CODE_SIGNING_ALLOWED=NO` 构建，模拟器上即是这种状态）
    /// 一旦真正触碰 CloudKit API（哪怕只是 `ModelConfiguration(cloudKitDatabase:)` 走到
    /// `ModelContainer(for:configurations:)` 内部），会在 CloudKit 框架内部直接 `trap` 崩溃退出
    /// 进程，而不是抛出可被 Swift `catch` 捕获的 `Error`——已实测复现（`xcodebuild test` 报
    /// 「test runner crashed before establishing connection」，控制台只留下一行
    /// `[CK] Significant issue ... com.apple.developer.icloud-services entitlement`
    /// 就整体退出，没有任何后续可捕获的错误路径）。反之，*已签名但缺少 iCloud 授权*
    /// （如 `Sign to Run Locally` 的本地临时签名、或已登录但未开通 iCloud 账户）场景下，
    /// CloudKit 会走正常的优雅失败路径、可以被 `try`/`catch` 捕获（如 `CKAccountStatusNoAccount`，
    /// 阶段7验证中同样实测复现）。因此“连尝试都不要尝试”的门槛判断（本方法）与
    /// “尝试后可能优雅失败的 `try`/`catch`”（`makeCloudKitContainer()` 的调用方）是两层
    /// 缺一不可的防线：前者挡住会直接崩溃的「完全无签名」场景，后者兜住会优雅抛错的
    /// 「已签名但暂不可用」场景。
    private static var hasICloudCapability: Bool {
        FileManager.default.ubiquityIdentityToken != nil
    }

    /// 生产启动路径（`MoodmentsApp` 非 UI 测试场景使用，见阶段7计划决策2）：优先尝试启用
    /// CloudKit 同步的容器；若进程本身没有 iCloud entitlement（未签名/未开通 iCloud
    /// capability，见 `hasICloudCapability`），**直接跳过 CloudKit 尝试**、不触碰任何
    /// CloudKit API；若已具备 entitlement 但因未登录 iCloud 账户等原因初始化失败，
    /// **回退到纯本地容器**而非让 App 无法启动——「宁可不同步也要能起动」（09-icloud-sync.md
    /// §9.3「离线优先」：本地 SwiftData 存储永远是唯一可信读写路径，CloudKit 同步是不阻塞任何
    /// UI 交互的锦上添花能力）。回退本身经由 `os.Logger` 记录（不是静默吞错——只是不能把这类
    /// 已被文档明确列为「可接受回退路径」的场景升级成用户可见的错误/崩溃）。
    /// - Returns: 实际启用的容器 + 是否成功启用了 CloudKit（供 `SyncStatusService` 判定用）。
    static func makeProductionContainer() -> (container: ModelContainer, cloudKitEnabled: Bool) {
        guard hasICloudCapability else {
            do {
                return (try makeLocalContainer(), false)
            } catch {
                fatalError("ModelContainer 初始化失败：\(error)")
            }
        }
        do {
            return (try makeCloudKitContainer(), true)
        } catch {
            let logger = Logger(subsystem: "com.moodments.app", category: "Persistence")
            logger.error(
                "CloudKit 容器初始化失败，回退本地容器（离线优先，见 09-icloud-sync.md §9.3）：\(String(describing: error), privacy: .private)"
            )
            do {
                return (try makeLocalContainer(), false)
            } catch {
                // 本地容器都无法建立才是真正不可恢复的启动错误，快速暴露（见 CLAUDE.md）。
                fatalError("ModelContainer 本地回退也初始化失败：\(error)")
            }
        }
    }
}
