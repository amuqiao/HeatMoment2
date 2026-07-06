import Foundation
import SwiftData

/// 首启默认标签预置（见 `docs/design/07-data-persistence.md` §4）：首次启动、`Tag` 表为空时
/// 预置「工作 / 生活 / 健康」三个默认标签（已裁决）。注意副作用：免费标签上限为 3，预置 3 个
/// 即占满免费额度——新用户要自建标签需先删除已有标签或升级 Pro，此为已知且可接受的取舍。
/// 非首次（`Tag` 表非空）不重复预置。本类型不区分生产/UI 测试场景，二者都需要这份默认数据
/// （UI 测试的标签额度拦截验收正是基于「默认预置已占满额度」这一口径，见阶段 3 计划）。
enum DefaultTagSeeder {
    static let defaultNames = ["工作", "生活", "健康"]

    /// - Throws: 底层 `ModelContext` 存取失败时抛出，不做静默兜底（见 CLAUDE.md「不擅自添加
    ///   兜底策略」）。
    @MainActor
    static func seedIfNeeded(_ context: ModelContext) throws {
        let existing = try context.fetchCount(FetchDescriptor<Tag>())
        guard existing == 0 else { return }
        for name in defaultNames {
            context.insert(Tag(name: name))
        }
        try context.save()
    }
}
