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

/// 心情色是跨时间轴节点、热力图、统计的独立数据语义色，**独立于主题主色**（依公理1，
/// 见 `product-mental-model.md`）：一次记录选择某个情绪，这个颜色应在节点/热力图/统计三处
/// 保持同一情绪身份，不得降为局部装饰、不得用统一色点替代。
///
/// **模式感知、绝不读主色**：`color(for:mode:)` 签名内没有 `AccentColorOption` 参数、函数体
/// 也不读取任何全局主色状态——这是「切主色时心情色不变」（公理1核心不变量）的结构性保证，
/// 而不是靠约定人工遵守。切**模式**（暗/亮）时心情色切到该情绪对应模式的取值（预期行为，
/// 区别于「切主色不变」）。
enum MoodColorPalette {
    /// - Parameters:
    ///   - mood: 情绪。
    ///   - mode: 当前外观模式，决定解析暗/亮两态中的哪一值；**不接受、不读取 `AccentColorOption`**。
    static func color(for mood: Mood, mode: ThemeMode) -> Color {
        let values = hexValues(for: mood)
        return Color(hex: mode == .dark ? values.dark : values.light)
    }

    /// (暗色态, 亮色态) 十六进制取值。
    ///
    /// 「正常」两态均为真机实测精确值（暗 `#15BEB4` / 亮 `#58BBB3`，见 05 §5.2.1/§5.4）。
    /// 其余 7 个情绪，设计文档只给出「暗色态·推导满值强度色」（05 §5.4 表格），真机未采集
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

    /// 弱提示/禁用文字，当前复用二级文字；单独暴露语义，便于后续亮/暗对比校准。
    static let mutedText = secondaryText

    /// 强调色实底上的文字/图标。
    static let onAccentText = Color.white

    /// 强调色实底上的弱化说明文字。
    static let onAccentSecondaryText = Color.white.opacity(0.85)

    /// 危险色实底上的文字/图标。
    static let onDangerText = Color.white

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

    /// Sheet 内分组面板/预览样本面板背景。
    static func sheetPanelBackground(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x2C2C2E) : Color(hex: 0xFFFFFF)
    }

    /// 分隔线/hairline。
    static func separator(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x3A3A3C) : Color(hex: 0xE5E5EA)
    }

    /// 热力图/心情统计「无记录」日期格底色（见 §5.7 MoodStatsView：「格子未命中为深灰
    /// `#454547`」）；`YearHeatmapView` 与 `MoodStatsView` 卡片1 共用同一空态语义（`HeatmapGridView`）。
    /// 亮色态数值文档未给出，按同类中性色语义近似取值 `[设计决策]`。
    static func heatmapEmptyCell(_ mode: ThemeMode) -> Color {
        mode == .dark ? Color(hex: 0x454547) : Color(hex: 0xD1D1D6)
    }

    /// 选中行/选中 chip 的主色弱填充。
    static func selectionFill(accent: Color) -> Color {
        accent.opacity(0.08)
    }

    /// 禁用态主按钮填充。
    static func accentDisabledFill(accent: Color) -> Color {
        accent.opacity(0.45)
    }

    /// 热力图月份定位高亮。
    static func selectedMonthFill(accent: Color) -> Color {
        accent.opacity(0.14)
    }

    /// 心情统计条形的空轨道。
    static func moodStatTrack(moodColor: Color) -> Color {
        moodColor.opacity(0.15)
    }

    /// 首页背景纹理颜色。
    static func homeTextureColor(accent: Color, mode: ThemeMode) -> Color {
        accent.opacity(mode == .dark ? 0.10 : 0.14)
    }

    /// 自定义首页背景图上的画布遮罩。
    static func customBackgroundOverlay(_ mode: ThemeMode) -> Color {
        canvasBackground(mode).opacity(mode == .dark ? 0.18 : 0.10)
    }

    /// 首页顶部 chrome 收起态的材质叠色。
    static func topChromeOverlay(_ mode: ThemeMode) -> Color {
        canvasBackground(mode).opacity(0.36)
    }

    /// 首页热力图上下文底部分隔线。
    static func heatmapSeparator(_ mode: ThemeMode) -> Color {
        timelineRail(mode).opacity(0.55)
    }

    /// FAB 阴影。
    static let floatingActionShadow = Color.black.opacity(0.20)

    /// 外观页真实预览卡自身容器背景。
    static func previewBackground(_ mode: ThemeMode) -> Color {
        sheetPanelBackground(mode)
    }

    /// 外观页真实预览卡弱描边/弱笔触。
    static func previewMuted(_ mode: ThemeMode) -> Color {
        separator(mode)
    }
}
