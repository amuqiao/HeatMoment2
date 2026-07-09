import Observation
import SwiftUI
import UIKit

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
    case customImage
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
    private(set) var customBackgroundImageURL: URL?
    private(set) var customBackgroundImageRevision = 0

    /// 载入时坏配置被回落默认值的轴数（见 05 §5.3.7「已修正 N 项本地偏好配置」）；
    /// `AppearanceThemeView` 据此展示一次性页内提示，不走全局 `.alert`。
    let correctedPreferenceCount: Int

    /// 主色/模式/纹理保存失败标记（见 05 §5.3.7：与照片显示保存失败分开反馈）。
    private(set) var appearanceSaveFailed = false
    /// 自定义背景图文件不可用时的本地修正提示，不复用“保存失败”语义。
    private(set) var customBackgroundImageRecovered = false
    /// 图片展示保存失败标记（见 05 §5.3.7：单独反馈，不与上面合并）。
    private(set) var photoDisplaySaveFailed = false

    private let store: AppearanceStore
    private var isCustomBackgroundImageImporting = false
    private var pendingCustomBackgroundImageData: Data?

    init(store: AppearanceStore = AppearanceStore()) {
        let (preference, correctedCount) = store.load()
        self.store = store
        self.mode = preference.mode
        self.accentColor = preference.accentColor
        self.backgroundTexture = preference.backgroundTexture
        self.imageDisplayMode = preference.imageDisplayMode
        self.correctedPreferenceCount = correctedCount
        restoreCustomBackgroundImageIfNeeded(preference.backgroundTexture)
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
        if newValue == .customImage, customBackgroundImageURL == nil {
            appearanceSaveFailed = true
            return
        }
        backgroundTexture = newValue
        persistCore()
    }

    func setCustomBackgroundImageData(_ data: Data) async {
        if isCustomBackgroundImageImporting {
            pendingCustomBackgroundImageData = data
            return
        }
        isCustomBackgroundImageImporting = true
        var nextData: Data? = data
        while let currentData = nextData {
            pendingCustomBackgroundImageData = nil
            await importCustomBackgroundImageData(currentData)
            nextData = pendingCustomBackgroundImageData
        }
        isCustomBackgroundImageImporting = false
    }

    private func importCustomBackgroundImageData(_ data: Data) async {
        do {
            let compressed = try await Task.detached(priority: .userInitiated) {
                try ImageCompressor.compressToJPEG(
                    data,
                    configuration: .init(
                        maxDimension: 2048,
                        jpegQuality: 0.82,
                        maxByteSize: 900 * 1024
                    )
                )
            }.value
            let writeTarget = store.customBackgroundImageWriteTarget()
            try await writeTarget.saveInBackground(compressed)
            customBackgroundImageURL = writeTarget.fileURL
            customBackgroundImageRevision += 1
            backgroundTexture = .customImage
            customBackgroundImageRecovered = false
            persistCore()
        } catch {
            appearanceSaveFailed = true
        }
    }

    func markAppearanceSaveFailed() {
        appearanceSaveFailed = true
    }

    func setImageDisplayMode(_ newValue: ImageDisplayMode) {
        imageDisplayMode = newValue
        persistPhotoDisplay()
    }

    private var currentPreference: AppearancePreference {
        AppearancePreference(
            mode: mode,
            accentColor: accentColor,
            backgroundTexture: backgroundTexture,
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

    private func restoreCustomBackgroundImageIfNeeded(_ texture: BackgroundTexture) {
        guard texture == .customImage else { return }
        do {
            guard
                let data = try store.loadCustomBackgroundImageData(),
                UIImage(data: data) != nil
            else {
                correctUnavailableCustomBackgroundImage()
                return
            }
            customBackgroundImageURL = store.customBackgroundImageFileURL
        } catch {
            correctUnavailableCustomBackgroundImage()
        }
    }

    private func correctUnavailableCustomBackgroundImage() {
        customBackgroundImageURL = nil
        backgroundTexture = AppearancePreference.default.backgroundTexture
        do {
            try store.save(currentPreference)
        } catch {
            assertionFailure("自定义背景图片不可用后的外观偏好修正保存失败：\(error)")
        }
        customBackgroundImageRecovered = true
    }

    /// 当前模式 + 主色解析后的稳定运行时 token。新增颜色消费优先经此对象理解语义边界。
    var tokens: AppThemeTokens { AppThemeTokens.resolve(mode: mode, accentColor: accentColor) }

    /// 首页时间轴场景样式入口。当前返回默认样式；未来皮肤管理应从这里切换样式包，
    /// 而不是让 timeline 子视图各自读取皮肤配置。
    var timelineSceneStyle: TimelineSceneStyle { .standard }

    /// 当前应用主题对应的系统 `ColorScheme`。任务容器页必须显式消费它，避免 SwiftUI
    /// 已呈现 sheet 中的 `List` / `NavigationBar` 和 token 模式脱节。
    var colorScheme: ColorScheme { mode.colorScheme }

    /// 当前主色，解析自 `accentColor` + `mode`（见 05 §5.3.2 Any/Dark 双值机制）。
    var accent: Color { tokens.accent }

    /// 外观页主色选项色块，与运行时主色解析同源。
    func accentSwatch(_ option: AccentColorOption) -> Color { tokens.accentSwatch(option) }

    /// 心情色（转发 `MoodPalette.color(_:mode:)`，见公理1）：View 层统一经此消费；
    /// 签名/实现均不读取 `accentColor`，是「切主色时心情色不变」的结构性保证。
    func moodColor(_ mood: Mood) -> Color { tokens.moodColor(mood) }

    /// 固定危险色：删除/失败等动作统一经此消费，不得误用
    /// `accent`（见 05 §5.3.5：危险色与主色解耦、不跟随主题）。
    var danger: Color { tokens.danger }

    /// 强调色实底上的文字/图标。
    var onAccentText: Color { tokens.onAccentText }

    /// 强调色实底上的弱化说明文字。
    var onAccentSecondaryText: Color { tokens.onAccentSecondaryText }

    /// 危险色实底上的文字/图标。
    var onDangerText: Color { tokens.onDangerText }

    /// 固定商业视觉，不随用户主色/模式变化。
    var commercialRed: Color { tokens.commercialRed }

    /// 固定商业页背景。
    var commercialBackground: Color { tokens.commercialBackground }

    /// 固定商业页面板。
    var commercialPanelBackground: Color { tokens.commercialPanelBackground }

    /// 固定商业页一级文字。
    var commercialPrimaryText: Color { tokens.commercialPrimaryText }

    /// 固定商业页二级文字。
    var commercialSecondaryText: Color { tokens.commercialSecondaryText }

    /// 固定商业页品牌块填充。
    var commercialLogoFill: Color { tokens.commercialLogoFill }

    /// 固定商业色实底文字/图标。
    var onCommercialText: Color { tokens.onCommercialText }

    /// 图片查看器固定沉浸黑底。
    var imageViewerBackground: Color { tokens.imageViewerBackground }

    /// 图片查看器 chrome 遮罩。
    var imageViewerChromeScrim: Color { tokens.imageViewerChromeScrim }

    /// 图片查看器 chrome 前景。
    var onImageViewerChrome: Color { tokens.onImageViewerChrome }

    /// 画布背景色（见 05 §5.2.1）。
    var canvasBackground: Color { tokens.canvasBackground }

    /// 气泡卡片背景色。
    var bubbleBackground: Color { tokens.bubbleBackground }

    /// 卡片主标题文字色。
    var bubbleTitleText: Color { tokens.bubbleTitleText }

    /// 卡片正文/摘要文字色。
    var bubbleBodyText: Color { tokens.bubbleBodyText }

    /// 时间轴竖线色。
    var timelineRail: Color { tokens.timelineRail }

    /// 输入框/Chip 填充色。
    var chipFill: Color { tokens.chipFill }

    /// 一级文字色。
    var primaryText: Color { tokens.primaryText }

    /// 二级文字色。
    var secondaryText: Color { tokens.secondaryText }

    /// 弱提示/禁用文字色。
    var mutedText: Color { tokens.mutedText }

    /// 顶部三入口图标的中性描边色（不跟随主色）。
    var neutralIconStroke: Color { tokens.neutralIconStroke }

    /// Sheet 顶层背景色（编辑器/设置等系统分组容器，见 §5.2.2）。
    var sheetBackground: Color { tokens.sheetBackground }

    /// Sheet 内分组面板背景。
    var sheetPanelBackground: Color { tokens.sheetPanelBackground }

    /// 分隔线/hairline。
    var separator: Color { tokens.separator }

    /// 热力图/心情统计「无记录」日期格底色（见 §5.7）。
    var heatmapEmptyCell: Color { tokens.heatmapEmptyCell }

    /// 选中行/选中 chip 的主色弱填充。
    var selectionFill: Color { tokens.selectionFill }

    /// 禁用态主按钮填充。
    var accentDisabledFill: Color { tokens.accentDisabledFill }

    /// 热力图月份定位高亮。
    var selectedMonthFill: Color { tokens.selectedMonthFill }

    /// 首页背景纹理颜色。
    var homeTextureColor: Color { tokens.homeTextureColor }

    /// 自定义首页背景图上的画布遮罩。
    var customBackgroundOverlay: Color { tokens.customBackgroundOverlay }

    /// 首页顶部 chrome 收起态的材质叠色。
    var topChromeOverlay: Color { tokens.topChromeOverlay }

    /// 首页热力图上下文底部分隔线。
    var heatmapSeparator: Color { tokens.heatmapSeparator }

    /// FAB 阴影。
    var floatingActionShadow: Color { tokens.floatingActionShadow }

    /// 外观页缩略样本自身容器背景。
    var previewBackground: Color { tokens.previewBackground }

    /// 外观页缩略样本弱描边/弱笔触。
    var previewMuted: Color { tokens.previewMuted }

    /// 心情统计条形的空轨道。
    func moodStatTrack(_ mood: Mood) -> Color {
        tokens.moodStatTrack(mood)
    }
}
