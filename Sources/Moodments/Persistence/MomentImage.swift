import Foundation
import SwiftData

/// 时刻的一张照片（图片存储策略见 `docs/design/07-data-persistence.md` §5）。
@Model
final class MomentImage {
    var id: UUID = UUID()
    /// 追加顺序，决定横向缩略图排列。
    var sortIndex: Int = 0
    var createdAt: Date = Date.now

    /// 原图数据，使用 `externalStorage` 交由 SwiftData/CloudKit 转存为文件/CKAsset，
    /// 而非内联在 CKRecord 字段中（见 07 §2 第5条）。
    @Attribute(.externalStorage) var imageData: Data = Data()

    var moment: Moment?

    init(
        id: UUID = UUID(),
        sortIndex: Int = 0,
        createdAt: Date = .now,
        imageData: Data = Data(),
        moment: Moment? = nil
    ) {
        self.id = id
        self.sortIndex = sortIndex
        self.createdAt = createdAt
        self.imageData = imageData
        self.moment = moment
    }
}
