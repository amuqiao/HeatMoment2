#if DEBUG
import Foundation
import SwiftData

/// UI 测试支持（仅 DEBUG 编译）：通过 launch arguments 让 App 使用隔离的内存容器、
/// 并按需预置一批记录，供依赖「可滚动/有数据」的 UI 测试使用。生产构建不含此代码。
///
/// - `-uiTestReset`：使用内存容器（空态、与磁盘隔离）。
/// - `-uiTestSeedMoments`：使用内存容器并预置 15 条 Moment（使时间轴可滚动，用于标题折叠等验收）。
enum UITestSupport {
    /// 是否应改用内存容器（测试隔离，不落盘、不需 iCloud 能力）。
    static var wantsInMemoryContainer: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("-uiTestReset") || args.contains("-uiTestSeedMoments")
    }

    /// 若带 `-uiTestSeedMoments` 且当前为空，则预置 15 条 Moment。
    @MainActor
    static func seedIfRequested(_ context: ModelContext) {
        guard ProcessInfo.processInfo.arguments.contains("-uiTestSeedMoments") else { return }
        // 不吞错：预检查失败应显式暴露（与下方 save 的处理一致，见 CLAUDE.md 快速失败铁律）。
        let existing: Int
        do {
            existing = try context.fetchCount(FetchDescriptor<Moment>())
        } catch {
            assertionFailure("UITest seed 预检查失败：\(error)")
            return
        }
        guard existing == 0 else { return }
        for index in 0..<15 {
            let moment = Moment()
            moment.title = "测试时刻 \(index + 1)"
            moment.bodyText = "用于 UI 测试的可滚动内容占位。"
            moment.occurredAt = Date(timeIntervalSinceNow: Double(-index) * 3600)
            context.insert(moment)
        }
        do {
            try context.save()
        } catch {
            assertionFailure("UITest seed 失败：\(error)")
        }
    }
}
#endif
