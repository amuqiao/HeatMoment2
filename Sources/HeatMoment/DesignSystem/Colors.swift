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
