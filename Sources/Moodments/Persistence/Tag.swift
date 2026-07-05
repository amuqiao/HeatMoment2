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

    /// 反向关系，见 `Moment.tags` 的 inverse。
    var moments: [Moment] = []

    init(id: UUID = UUID(), name: String = "", createdAt: Date = .now, moments: [Moment] = []) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.moments = moments
    }
}
