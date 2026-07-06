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
/// **状态**：四轴均为 `private(set)`——外部只能经下方 4 个语义 setter 修改，结构上保证
/// 「任何一次修改都会同时触发持久化」，不存在绕过 `AppearanceStore` 直接改视觉状态的路径。
/// **持久化**：`init` 用 `AppearanceStore.load()` 回填四轴 + `correctedPreferenceCount`
/// （坏配置回落默认值的计数，见 05 §5.3.7）；每个 setter 落库前先乐观更新内存态（当前界面
/// 立即生效），再 `try store.save(...)`，失败置对应失败标记但**不回滚**已生效的视觉状态
/// （见 08-architecture.md §4.3、05 §5.3.7）。
///
/// 本类型同时承担「当前 ColorScheme 下强调色语义解析」职责（见 08 §4.3）：View 层不直接读取
/// 十六进制值，统一通过本类型暴露的已解析颜色属性消费；心情色/危险色分别经 `moodColor(_:)`/
/// `danger` 转发，**均不读取 `accentColor`**，是「心情色/危险色独立于主色」（公理1、05 §5.3.5/
/// §5.3.6）的结构性保证。
@MainActor
@Observable
final class ThemeManager {
    private(set) var mode: ThemeMode
    private(set) var accentColor: AccentColorOption
    private(set) var backgroundTexture: BackgroundTexture
    private(set) var imageDisplayMode: ImageDisplayMode

    /// 载入时坏配置被回落默认值的轴数（见 05 §5.3.7「已修正 N 项本地偏好配置」）；
    /// `AppearanceThemeView` 据此展示一次性页内提示，不走全局 `.alert`。
    let correctedPreferenceCount: Int

    /// 主色/模式/纹理保存失败标记（见 05 §5.3.7：与照片显示保存失败分开反馈）。
    private(set) var appearanceSaveFailed = false
    /// 图片展示保存失败标记（见 05 §5.3.7：单独反馈，不与上面合并）。
    private(set) var photoDisplaySaveFailed = false

    private let store: AppearanceStore

    init(store: AppearanceStore = AppearanceStore()) {
        let (preference, correctedCount) = store.load()
        self.store = store
        self.mode = preference.mode
        self.accentColor = preference.accentColor
        self.backgroundTexture = preference.backgroundTexture
        self.imageDisplayMode = preference.imageDisplayMode
        self.correctedPreferenceCount = correctedCount
    }

    // MARK: - 乐观更新语义 setter（见类型头部说明）

    func setMode(_ newValue: ThemeMode) {
        mode = newValue
        persistCore()
    }

    func setAccentColor(_ newValue: AccentColorOption) {
        accentColor = newValue
        persistCore()
    }

    func setBackgroundTexture(_ newValue: BackgroundTexture) {
        backgroundTexture = newValue
        persistCore()
    }

    func setImageDisplayMode(_ newValue: ImageDisplayMode) {
        imageDisplayMode = newValue
        persistPhotoDisplay()
    }

    private var currentPreference: AppearancePreference {
        AppearancePreference(
            mode: mode, accentColor: accentColor, backgroundTexture: backgroundTexture,
            imageDisplayMode: imageDisplayMode
        )
    }

    private func persistCore() {
        do {
            try store.save(currentPreference)
            appearanceSaveFailed = false
        } catch {
            appearanceSaveFailed = true
        }
    }

    private func persistPhotoDisplay() {
        do {
            try store.save(currentPreference)
            photoDisplaySaveFailed = false
        } catch {
            photoDisplaySaveFailed = true
        }
    }

    /// 当前主色，解析自 `accentColor` + `mode`（见 05 §5.3.2 Any/Dark 双值机制）。
    var accent: Color { accentColor.color(for: mode) }

    /// 心情色（转发 `MoodColorPalette.color(for:mode:)`，见公理1）：View 层统一经此消费，
    /// 不直接调用 `MoodColorPalette`；签名/实现均不读取 `accentColor`，是「切主色时心情色
    /// 不变」的结构性保证（见 `MoodColorPalette` 头部说明）。
    func moodColor(_ mood: Mood) -> Color { MoodColorPalette.color(for: mood, mode: mode) }

    /// 固定危险色（转发 `SemanticColor.danger`）：删除/失败等动作统一经此消费，不得误用
    /// `accent`（见 05 §5.3.5：危险色与主色解耦、不跟随主题）。
    var danger: Color { SemanticColor.danger }

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
