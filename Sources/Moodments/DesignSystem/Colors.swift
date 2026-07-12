import SwiftUI

// MARK: - 十六进制颜色构造

extension Color {
    /// 从 24-bit 十六进制值构造不透明颜色，如 `Color(hex: 0x121221)`。
    init(hex: UInt32) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}

// MARK: - 情绪 → 心情色（见 docs/current/implementation-truth.md §5.4）

/// 心情色是跨时间轴节点、热力图、统计的独立数据语义色，**独立于主题主色**（依公理1，
/// 见 `product-mental-model.md`）：一次记录选择某个情绪，这个颜色应在节点/热力图/统计三处
/// 保持同一情绪身份，不得降为局部装饰、不得用统一色点替代。
///
/// **模式感知、绝不读主色**：`color(for:mode:)` 签名内没有 `AccentColorOption` 参数、函数体
/// 也不读取任何全局主色状态——这是「切主色时心情色不变」（公理1核心不变量）的结构性保证，
/// 而不是靠约定人工遵守。切**模式**（暗/亮）时心情色切到该情绪对应模式的取值（预期行为，
/// 区别于「切主色不变」）。
enum MoodPalette {
    /// - Parameters:
    ///   - mood: 情绪。
    ///   - mode: 当前外观模式，决定解析暗/亮两态中的哪一值；**不接受、不读取 `AccentColorOption`**。
    static func color(_ mood: Mood, mode: ThemeMode) -> Color {
        let values = hexValues(for: mood)
        return Color(hex: mode == .dark ? values.dark : values.light)
    }

    static func statTrack(moodColor: Color) -> Color {
        moodColor.opacity(0.15)
    }

    /// (暗色态, 亮色态) 十六进制取值。
    ///
    /// 「正常」两态均为真机实测精确值（暗 `#15BEB4` / 亮 `#58BBB3`，见 docs/current/implementation-truth.md §5.2.1/§5.4）。
    /// 其余 7 个情绪，早期取色资料只给出「暗色态·推导满值强度色」，真机未采集
    /// 这些情绪在亮色模式下的实际取值——**亮色态暂沿用同一数值** `[设计决策待确认]`，待后续
    /// 真机复核后再按情绪逐一区分两态；此处「待确认」的只是「两态是否应有差异」，不影响
    /// 公理1「独立于主色」这一结构性保证（该保证由签名不含主色参数决定，与本表取值无关）。
    private static func hexValues(for mood: Mood) -> (dark: UInt32, light: UInt32) {
        switch mood {
        case .normal: (0x15BEB4, 0x58BBB3)
        case .happy: (0x2C9749, 0x2C9749)
        case .sad: (0x1F478F, 0x1F478F)
        case .anxious: (0x830B63, 0x830B63)
        case .fearful: (0x403292, 0x403292)
        case .angry: (0xB8332E, 0xB8332E)
        case .disgusted: (0x475435, 0x475435)
        case .motivated: (0xB17521, 0xB17521)
        }
    }
}

// MARK: - 6 主色（见 docs/current/implementation-truth.md §5.3.2）

/// 6 个可选主色，默认「紫罗兰」。每个主色是 Any/Dark 双值，由 `ThemeManager.mode` 显式解析
/// （而非依赖系统 `ColorScheme`，见 `ThemeManager` 顶部注释：应用的"模式"是用户在外观页里
/// 自行选择的独立设置，不等同于系统深色模式开关）。
enum AccentColorOption: String, CaseIterable, Identifiable, Sendable {
    /// 紫色（靛蓝，色板首位）。
    case purple
    case red
    case orange
    case green
    case cyan
    /// 紫罗兰（默认，色板末位）。
    case violet

    var id: String { rawValue }
}
