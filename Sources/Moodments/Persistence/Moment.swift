import Foundation
import SwiftData

/// 一条生活记忆（见公理层「时刻」对象）。字段与 CloudKit 兼容约束见
/// `docs/design/07-data-persistence.md` §2、§3——不加 `@Attribute(.unique)`，
/// 所有属性有默认值/Optional，关系可选且删除规则只用 `.cascade` / `.nullify`。
@Model
final class Moment {
    /// 本地唯一标识；不加 `@Attribute(.unique)`——CloudKit 下 `.unique` 不生效，
    /// 唯一性由 UUID 值本身保证，加了反而误导。
    var id: UUID = UUID()

    var title: String = ""
    /// 正文；避免用 `body` 以免与 SwiftUI 语义混淆。
    var bodyText: String = ""

    /// 发生时间：用户可编辑的"事情发生的时间"，支持任意过去/未来日期，用于补记。
    var occurredAt: Date = Date.now

    /// 系统记录创建时间：审计用途，不可编辑，不参与排序展示。
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    /// 情绪：落库为 `Int` rawValue（CloudKit 约束，见 07 §2 第6条），
    /// 对外通过计算属性 `mood` 暴露强类型 `Mood`（见 `Models/Mood.swift`）。
    var moodRawValue: Int = Mood.normal.rawValue
    var mood: Mood {
        get { Mood(rawValue: moodRawValue) ?? .normal }
        set { moodRawValue = newValue.rawValue }
    }

    @Relationship(deleteRule: .nullify, inverse: \Tag.moments)
    var tags: [Tag] = []

    @Relationship(deleteRule: .cascade, inverse: \MomentImage.moment)
    var images: [MomentImage] = []

    /// 软删除生命周期字段（见公理「删除是生命周期」与 07 §3）。
    ///
    /// **实现取舍（偏离 07-data-persistence.md 字面代码样例）**：文档样例直接用
    /// `var isDeleted: Bool = false` 作为存储属性，但经实测验证，SwiftData 在
    /// `Bool` 存储属性使用 `is` 前缀命名（如 `isDeleted`）时，Objective-C KVC 会把
    /// 布尔访问器的 key 去掉 `is` 前缀（`isDeleted` → `deleted`），与 SwiftData/Core
    /// Data 生成的底层映射冲突，导致 `ModelContext.save()` 后该字段被错误重置为
    /// 默认值（可用一个最小复现工程稳定复现：赋值为 `true` 并 `save()` 后，同一
    /// 存活对象读回的值又变回 `false`）。故此处改用不带 `is` 前缀的存储属性
    /// `deletedFlag`，对外仍通过计算属性 `isDeleted`暴露文档约定的字段名/语义
    /// （与 `moodRawValue`→`mood` 的做法一致）；`#Predicate` 查询须直接用
    /// `deletedFlag`，见 `MomentRepository`。
    var deletedFlag: Bool = false
    var isDeleted: Bool {
        get { deletedFlag }
        set { deletedFlag = newValue }
    }
    var deletedAt: Date?

    init(
        id: UUID = UUID(),
        title: String = "",
        bodyText: String = "",
        occurredAt: Date = .now,
        createdAt: Date = .now,
        updatedAt: Date = .now,
        mood: Mood = .normal,
        tags: [Tag] = [],
        images: [MomentImage] = [],
        isDeleted: Bool = false,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.bodyText = bodyText
        self.occurredAt = occurredAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.moodRawValue = mood.rawValue
        self.tags = tags
        self.images = images
        self.deletedFlag = isDeleted
        self.deletedAt = deletedAt
    }
}
