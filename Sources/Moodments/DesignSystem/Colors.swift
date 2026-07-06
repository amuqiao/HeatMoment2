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

// MARK: - 情绪 → 心情色（见 05-design-system.md §5.4）

/// 心情色是跨时间轴节点、热力图、统计的独立数据语义色，不随主题模式/主色变化（依公理1，
/// 见 `product-mental-model.md`）：一次记录选择某个情绪，这个颜色应在节点/热力图/统计三处
/// 保持同一情绪身份，不得降为局部装饰、不得用统一色点替代。
///
/// 阶段 2 按设计文档给出的**深色态**取值实现（§5.4 表格「推导满值强度色」列，「正常」用真机
/// 实测色）；亮色态数值文档未给全 8 项，留待后续涉及亮色模式的页面按需补齐。
enum MoodColorPalette {
    static func color(for mood: Mood) -> Color {
        switch mood {
        case .normal: Color(hex: 0x15BEB4)
        case .happy: Color(hex: 0x2C9749)
        case .sad: Color(hex: 0x1F478F)
        case .anxious: Color(hex: 0x830B63)
        case .fearful: Color(hex: 0x403292)
        case .angry: Color(hex: 0xB8332E)
        case .disgusted: Color(hex: 0x475435)
        case .motivated: Color(hex: 0xB17521)
        }
    }
}

// MARK: - 6 主色（见 05-design-system.md §5.3.2）

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

    /// - Parameter mode: 当前外观模式，决定解析暗/亮两态中的哪一值。
    func color(for mode: ThemeMode) -> Color {
        switch (self, mode) {
        case (.purple, _): Color(hex: 0x5E5BE6)
        case (.red, .dark): Color(hex: 0xFC5447)
        case (.red, .light): Color(hex: 0xE9604F)
        case (.orange, .dark): Color(hex: 0xF7A213)
        case (.orange, .light): Color(hex: 0xF39911)
        case (.green, .dark): Color(hex: 0x2DAD74)
        case (.green, .light): Color(hex: 0x228859)
        case (.cyan, _): Color(hex: 0x00C7BD)
        case (.violet, .dark): Color(hex: 0xB678F5)
        case (.violet, .light): Color(hex: 0x8E51AE)
        }
    }
}

// MARK: - 语义色（见 05-design-system.md §5.2）

/// 时间轴品牌画布 + 系统分组容器的语义色，按 `ThemeManager.mode` 双值解析。
/// 心情色、危险色不在此列——它们独立于「模式」，见 `MoodColorPalette` 与 `SemanticColor.danger`。
enum SemanticColor {
    /// 页面背景（含网格/点阵纹理），见 §5.2.1。
    static func canvasBackground(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x121221) : Color(hex: 0xF2F2F6)
    }

    /// 气泡卡片背景。
    static func bubbleBackground(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x3A3A40) : Color(hex: 0xFFFFFF)
    }

    /// 卡片主标题文字。
    static func bubbleTitleText(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0xEBEBED) : Color(hex: 0x0D0C2B)
    }

    /// 卡片正文/摘要文字（secondary）。
    static func bubbleBodyText(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0xC7C7CC) : Color(hex: 0x6C6C70)
    }

    /// 时间轴竖线。
    static func timelineRail(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x2A2A38) : Color(hex: 0xE3E2EA)
    }

    /// 输入框/Chip 填充，见 §5.2.2。
    static func chipFill(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x48484B) : Color(hex: 0xE9E9EC)
    }

    /// 一级文字。
    static func primaryText(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0xF2F2F7) : Color(hex: 0x0D0C2B)
    }

    /// 二级/占位文字，两态数值相同（Apple 官方定义，见 §5.2.2）。
    static let secondaryText = Color(hex: 0x8E8E93)

    /// 固定危险色（删除/失败/Pro 页高风险动作），与主色/模式解耦，不跟随主题变化（见 §5.3.5）。
    static let danger = Color(hex: 0xFC5447)

    /// 顶部三入口图标线性描边中性色，不跟随主色（见 §5.6 组件规格：暗色下浅灰/白、亮色下深灰/黑）。
    /// 文档未给出精确取色值，此处按同类中性色语义近似取值 `[设计决策]`。
    static func neutralIconStroke(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0xEBEBF5) : Color(hex: 0x3C3C43)
    }

    /// Sheet 顶层背景（编辑器/设置等系统分组容器，见 §5.2.2：暗色 `#1C1C1E` / 亮色
    /// 标准 iOS `systemGroupedBackground` 浅色值 `#F2F2F7`）。阶段 3 供 `MomentEditorView` 使用。
    static func sheetBackground(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x1C1C1E) : Color(hex: 0xF2F2F7)
    }
}
