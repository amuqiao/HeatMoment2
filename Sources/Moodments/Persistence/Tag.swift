import Foundation
import SwiftData

/// 时刻的主题归类线索（见公理层「标签」对象：归类关系，不是所有权）。
/// 字段契约见 `docs/design/07-data-persistence.md` §4。
@Model
final class Tag {
    var id: UUID = UUID()
    /// 唯一性由应用层保存前查重保证（CloudKit 不支持 `.unique`，见 07 §2 第2条）。
    var name: String = ""
    var createdAt: Date = Date.now

    /// 反向关系，见 `Moment.tags`/`tagsStorage` 的 inverse 与阶段7 CloudKit 兼容存储说明
    /// （`Optional` 存储列 + 非 `Optional` 计算属性对外暴露，同一模式见 `Moment.swift`）。
    /// 不标 `private`（而非 `fileprivate`/`internal` 更宽）：`Moment.swift` 的
    /// `@Relationship(inverse: \Tag.momentsStorage)` 需要跨文件引用该 keypath。
    var momentsStorage: [Moment]?
    var moments: [Moment] {
        get { momentsStorage ?? [] }
        set { momentsStorage = newValue }
    }

    init(id: UUID = UUID(), name: String = "", createdAt: Date = .now, moments: [Moment] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        // 直接写存储列，理由同 `Moment.init` 对 `tagsStorage`/`imagesStorage` 的处理。
        self.momentsStorage = moments
    }
}
