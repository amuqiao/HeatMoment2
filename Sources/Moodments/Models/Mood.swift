import Foundation

/// 情绪枚举：8 种并列情绪，非线性量表（依公理层《产品心智模型》——心情是时刻的情绪身份）。
///
/// `rawValue` 一旦发布上线即视为**持久化契约**（见 `docs/product-mental-model.md` §1）：
/// - 禁止重排、禁止复用旧值；
/// - 只能在末尾追加新 case（若产品未来扩展情绪种类）；
/// - `Mood.allCases`（rawValue 升序）必须在情绪选择器 / 心情统计 / 筛选候选列表三处保持完全一致的展示顺序。
enum Mood: Int, CaseIterable, Codable, Identifiable, Sendable {
    case normal = 0  // 😀 正常   Normal
    case happy = 1  // 😄 开心   Happy
    case sad = 2  // 🙁 难过   Sad
    case anxious = 3  // 🥶 焦虑   Anxious
    case fearful = 4  // 😱 恐惧   Fearful
    case angry = 5  // 😡 愤怒   Angry
    case disgusted = 6  // 🤮 厌恶   Disgusted
    case motivated = 7  // 😎 激励   Motivated

    var id: Int { rawValue }

    /// emoji 字面量，与情绪选择器 / 时间轴节点 / 心情统计条完全一致（见 docs/product-mental-model.md §1.4）。
    var emoji: String {
        switch self {
        case .normal: "😀"
        case .happy: "😄"
        case .sad: "🙁"
        case .anxious: "🥶"
        case .fearful: "😱"
        case .angry: "😡"
        case .disgusted: "🤮"
        case .motivated: "😎"
        }
    }

    /// i18n key，如 `"mood.normal.name"`；对应 zh-Hans / en 两套本地化文案（见 docs/product-mental-model.md §1.1）。
    var localizedNameKey: String {
        switch self {
        case .normal: "mood.normal.name"
        case .happy: "mood.happy.name"
        case .sad: "mood.sad.name"
        case .anxious: "mood.anxious.name"
        case .fearful: "mood.fearful.name"
        case .angry: "mood.angry.name"
        case .disgusted: "mood.disgusted.name"
        case .motivated: "mood.motivated.name"
        }
    }
}
