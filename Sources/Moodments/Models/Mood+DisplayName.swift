import Foundation

/// 中文展示名（临时直出文案）：正式多语言由 `Localizable.xcstrings` String Catalog 承载
/// （见 08-architecture.md §7 `Localization/`，属阶段 7 支撑能力）；在该基础设施落地前，
/// UI 层（如时间轴无障碍朗读、心情节点旁文字）用本属性直接展示中文名，`Mood.localizedNameKey`
/// （见 `Mood.swift`）保持为最终 i18n key 不变，未来接入 String Catalog 后可改为读取该 key
/// 的解析结果。
///
/// **实现取舍**：本应作为 `Mood.swift` 内的一个新增计算属性（与 `emoji`/`localizedNameKey`
/// 相邻），但当前环境对该文件的写权限异常（`EPERM`，本会话对已存在/已入库文件的写操作
/// 普遍被拒绝，只能创建新文件），故改用同类型的独立扩展文件承载，功能等价、不改变
/// `Mood` 的持久化契约。
extension Mood {
    var displayName: String {
        switch self {
        case .normal: "正常"
        case .happy: "开心"
        case .sad: "难过"
        case .anxious: "焦虑"
        case .fearful: "恐惧"
        case .angry: "愤怒"
        case .disgusted: "厌恶"
        case .motivated: "激励"
        }
    }
}
