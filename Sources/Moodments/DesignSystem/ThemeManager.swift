import Observation
import SwiftUI

/// 外观模式（暗/亮），见 05-design-system.md §5.3.1。
///
/// 这是应用**自己的**主题开关（在 `AppearanceThemeView` 里选择），不等同于系统「深色模式」，
/// 二者语义不同——本 App 的默认外观是暗色 + 紫罗兰，且不跟随系统外观自动切换
/// （`[设计决策]`，与文档「默认外观是深色模式」的产品设定一致）。
enum ThemeMode: String, CaseIterable, Sendable {
    case dark
    case light
}

/// 背景纹理（见 05 §5.3.3）：仅影响 `TimelineHomeView` 背景渲染，不影响卡片/文字/其它页面。
enum BackgroundTexture: String, CaseIterable, Sendable {
    case grid
    case dot
    case none
}

/// 图片展示方式（见 05 §5.3.4）：内容行为偏好，与模式/主色/纹理三条外观轴独立，
/// 只改变气泡内图片浏览方式，不改变颜色。
enum ImageDisplayMode: String, CaseIterable, Sendable {
    case scroll
    case carousel
}

/// 组合式主题：模式 × 主色 × 背景纹理 × 图片展示（见 05-design-system.md §5.3）。
///
/// 阶段 2 仅给出默认值（暗色 + 紫罗兰 + 网格 + 滚动）并通过 `@Environment` 注入全树；
/// 持久化（`AppearancePreference`）、乐观更新、失败反馈、完整的 `AppearanceThemeView`
/// 外观设置页留阶段 6 实现（见 05 §5.3.7、08-architecture.md §4.3）。
///
/// 本类型同时承担「当前 ColorScheme 下强调色语义解析」职责（见 08 §4.3）：View 层不直接读取
/// 十六进制值，统一通过本类型暴露的已解析颜色属性消费。
@MainActor
@Observable
final class ThemeManager {
    var mode: ThemeMode
    var accentColor: AccentColorOption
    var backgroundTexture: BackgroundTexture
    var imageDisplayMode: ImageDisplayMode

    init(
        mode: ThemeMode = .dark,
        accentColor: AccentColorOption = .violet,
        backgroundTexture: BackgroundTexture = .grid,
        imageDisplayMode: ImageDisplayMode = .scroll
    ) {
        self.mode = mode
        self.accentColor = accentColor
        self.backgroundTexture = backgroundTexture
        self.imageDisplayMode = imageDisplayMode
    }

    /// 当前主色，解析自 `accentColor` + `mode`（见 05 §5.3.2 Any/Dark 双值机制）。
    var accent: Color { accentColor.color(for: mode) }

    /// 画布背景色（见 05 §5.2.1）。
    var canvasBackground: Color { SemanticColor.canvasBackground(mode) }

    /// 气泡卡片背景色。
    var bubbleBackground: Color { SemanticColor.bubbleBackground(mode) }

    /// 卡片主标题文字色。
    var bubbleTitleText: Color { SemanticColor.bubbleTitleText(mode) }

    /// 卡片正文/摘要文字色。
    var bubbleBodyText: Color { SemanticColor.bubbleBodyText(mode) }

    /// 时间轴竖线色。
    var timelineRail: Color { SemanticColor.timelineRail(mode) }

    /// 输入框/Chip 填充色。
    var chipFill: Color { SemanticColor.chipFill(mode) }

    /// 一级文字色。
    var primaryText: Color { SemanticColor.primaryText(mode) }

    /// 顶部三入口图标的中性描边色（不跟随主色）。
    var neutralIconStroke: Color { SemanticColor.neutralIconStroke(mode) }

    /// Sheet 顶层背景色（编辑器/设置等系统分组容器，见 §5.2.2）。
    var sheetBackground: Color { SemanticColor.sheetBackground(mode) }

    /// 热力图/心情统计「无记录」日期格底色（见 §5.7）。
    var heatmapEmptyCell: Color { SemanticColor.heatmapEmptyCell(mode) }
}
