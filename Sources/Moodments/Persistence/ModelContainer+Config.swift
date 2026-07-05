import Foundation
import SwiftData

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

    // MARK: - CloudKit 私有库配置（阶段 7 接 entitlements 后启用）
    //
    // 以下配置写好但默认不被调用：`Project.yml` 尚未开启 `CODE_SIGN_ENTITLEMENTS`/iCloud
    // capability（见 `Project.yml` 中「阶段 7 接 iCloud/StoreKit 时再启用 entitlements」注释），
    // 阶段 1 若启用会导致本地构建因缺少 iCloud 能力签名失败，故保持注释、不参与编译路径。
    //
    // static func makeCloudKitContainer() throws -> ModelContainer {
    //     let configuration = ModelConfiguration(
    //         schema: schema,
    //         isStoredInMemoryOnly: false,
    //         cloudKitDatabase: .private("iCloud.com.moodments.app")
    //     )
    //     return try ModelContainer(for: schema, configurations: [configuration])
    // }
}
