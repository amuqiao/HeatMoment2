import SwiftUI

/// 心情色是跨时间轴节点、热力图、统计的独立数据语义色，**独立于主题主色**（依公理1）。
///
/// **模式感知、绝不读主色**：`color(_:mode:)` 签名内没有 `AccentColorOption` 参数、函数体
/// 也不读取任何全局主色状态。这是「切主色时心情色不变」的结构性保证。
enum MoodPalette {
    static func color(_ mood: Mood, mode: ThemeMode) -> Color {
        let values = hexValues(for: mood)
        return Color(hex: mode == .dark ? values.dark : values.light)
    }

    static func statTrack(moodColor: Color) -> Color {
        moodColor.opacity(0.15)
    }

    /// (暗色态, 亮色态) 十六进制取值。
    ///
    /// 「正常」两态均为真机实测精确值（暗 `#15BEB4` / 亮 `#58BBB3`）。
    /// 其余 7 个情绪目前沿用暗色态满值强度色，待真机复核后再按模式区分。
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
