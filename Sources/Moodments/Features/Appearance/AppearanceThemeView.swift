import PhotosUI
import SwiftUI

private enum BackgroundImageLoadError: Error {
    case emptyData
}

/// 外观主题子页（见 `docs/design/04-screen-specs.md` §4.15、05-design-system.md §5.3/§5.7）：
/// 模式 / 颜色（主色）/ 网格（背景纹理）/ 图片（图片展示）4 个分组，**乐观更新即时生效**——
/// 无「保存」按钮，点选后 `ThemeManager` 立即改内存态、当前界面立即用新值（本页自身背景/
/// 强调色随之实时反映，即「其下真实界面即预览」，见 08-architecture.md §4.3）。
///
/// 三类异常反馈均为**页内非模态提示**、不走全局 `.alert`（见 05 §5.3.7、CLAUDE.md 阶段6决策3：
/// 外观异常是统一错误通道的例外）：主色/模式/纹理保存失败、图片显示保存失败分开展示；
/// 载入时坏配置回落默认值的计数展示「已修正 N 项本地偏好配置」。
struct AppearanceThemeView: View {
    @Environment(ThemeManager.self) private var theme
    @State private var customBackgroundPickerItem: PhotosPickerItem?

    var body: some View {
        List {
            if theme.correctedPreferenceCount > 0 {
                Section {
                    // 良性信息态（自愈成功的告知），非错误——用主色而非危险红，与下方两条
                    // 「保存失败」的危险提示做视觉区分。
                    inlineNotice(
                        text: "已修正 \(theme.correctedPreferenceCount) 项本地偏好配置",
                        identifier: "appearanceCorrectedNotice",
                        color: theme.accent
                    )
                }
                .taskGroupedRowBackground(theme)
            }
            if theme.appearanceSaveFailed {
                Section {
                    inlineNotice(
                        text: "外观设置保存失败，请稍后重试",
                        identifier: "appearanceSaveFailedNotice",
                        color: theme.danger
                    )
                }
                .taskGroupedRowBackground(theme)
            }
            if theme.customBackgroundImageRecovered {
                Section {
                    inlineNotice(
                        text: "自定义背景图片不可用，已恢复默认背景",
                        identifier: "customBackgroundImageRecoveredNotice",
                        color: theme.danger
                    )
                }
                .taskGroupedRowBackground(theme)
            }
            if theme.photoDisplaySaveFailed {
                Section {
                    inlineNotice(
                        text: "照片显示设置保存失败，请稍后重试",
                        identifier: "photoDisplaySaveFailedNotice",
                        color: theme.danger
                    )
                }
                .taskGroupedRowBackground(theme)
            }

            Section("预览") {
                AppearanceThemePreviewView()
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("模式") {
                modeRow(.dark, label: "暗色")
                modeRow(.light, label: "亮色")
            }
            .taskGroupedRowBackground(theme)

            Section("颜色") {
                ForEach(AccentColorOption.allCases) { option in
                    accentRow(option)
                }
            }
            .taskGroupedRowBackground(theme)

            Section("背景") {
                textureRow(.grid, label: "网格线")
                textureRow(.dot, label: "点阵")
                textureRow(.none, label: "无")
                customBackgroundImageRow
                #if DEBUG
                    if UITestSupport.wantsBackgroundImageInjectionHook {
                        Button("注入测试背景图") {
                            Task {
                                await theme.setCustomBackgroundImageData(
                                    UITestSupport.makeSyntheticBackgroundImageData()
                                )
                            }
                        }
                        .accessibilityIdentifier("appearanceCustomBackgroundInjectButton")
                    }
                #endif
            }
            .taskGroupedRowBackground(theme)

            Section("图片") {
                imageModeRow(.scroll, label: "滚动")
                imageModeRow(.carousel, label: "轮播")
            }
            .taskGroupedRowBackground(theme)
        }
        .taskGroupedListBackground(theme)
        .navigationTitle("主题颜色")
        .themedTaskContainer(theme)
        .onChange(of: customBackgroundPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importCustomBackgroundImage(from: newItem)
                customBackgroundPickerItem = nil
            }
        }
    }

    private func inlineNotice(text: String, identifier: String, color: Color) -> some View {
        Text(text)
            .font(AppTypography.caption)
            .foregroundStyle(color)
            .accessibilityIdentifier(identifier)
    }

    private func modeRow(_ mode: ThemeMode, label: String) -> some View {
        optionRow(
            label: label,
            isSelected: theme.mode == mode,
            identifier: "appearanceModeOption-\(mode.rawValue)",
            accessibilityLabel: "模式：\(label)"
        ) {
            theme.setMode(mode)
        }
    }

    private func accentRow(_ option: AccentColorOption) -> some View {
        let name = Self.accentDisplayName(option)
        return Button {
            theme.setAccentColor(option)
        } label: {
            HStack {
                Circle()
                    .fill(theme.accentSwatch(option))
                    .frame(width: 24, height: 24)
                Text(name).foregroundStyle(theme.primaryText)
                Spacer()
                if theme.accentColor == option {
                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                }
            }
        }
        .accessibilityIdentifier("appearanceAccentOption-\(option.rawValue)")
        .accessibilityLabel(Text("主色：\(name)"))
        .accessibilityAddTraits(theme.accentColor == option ? [.isSelected] : [])
    }

    private func textureRow(_ texture: BackgroundTexture, label: String) -> some View {
        optionRow(
            label: label,
            isSelected: theme.backgroundTexture == texture,
            identifier: "appearanceTextureOption-\(texture.rawValue)",
            accessibilityLabel: "背景纹理：\(label)"
        ) {
            theme.setBackgroundTexture(texture)
        }
    }

    private func imageModeRow(_ mode: ImageDisplayMode, label: String) -> some View {
        optionRow(
            label: label,
            isSelected: theme.imageDisplayMode == mode,
            identifier: "appearanceImageModeOption-\(mode.rawValue)",
            accessibilityLabel: "图片展示：\(label)"
        ) {
            theme.setImageDisplayMode(mode)
        }
    }

    private var customBackgroundImageRow: some View {
        let isSelected = theme.backgroundTexture == .customImage
        let primaryText = theme.primaryText
        let accent = theme.accent

        return PhotosPicker(selection: $customBackgroundPickerItem, matching: .images) {
            HStack {
                Text("自定义图片").foregroundStyle(primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(accent)
                }
            }
        }
        .accessibilityIdentifier("appearanceTextureOption-customImage")
        .accessibilityLabel(Text("背景纹理：自定义图片"))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private func optionRow(
        label: String, isSelected: Bool, identifier: String, accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(label).foregroundStyle(theme.primaryText)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark").foregroundStyle(theme.accent)
                }
            }
        }
        .accessibilityIdentifier(identifier)
        .accessibilityLabel(Text(accessibilityLabel))
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private static func accentDisplayName(_ option: AccentColorOption) -> String {
        switch option {
        case .purple: "紫色"
        case .red: "红色"
        case .orange: "橙色"
        case .green: "绿色"
        case .cyan: "青色"
        case .violet: "紫罗兰"
        }
    }

    private func importCustomBackgroundImage(from item: PhotosPickerItem) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                theme.markAppearanceSaveFailed()
                assertionFailure("自定义背景图片读取失败：\(BackgroundImageLoadError.emptyData)")
                return
            }
            await theme.setCustomBackgroundImageData(data)
        } catch {
            theme.markAppearanceSaveFailed()
            assertionFailure("自定义背景图片读取失败：\(error)")
        }
    }
}

private struct AppearanceThemePreviewView: View {
    @Environment(ThemeManager.self) private var theme

    private static var heatmapPreviewMoods: [Mood?] {
        [.normal, nil, .happy, .motivated] + [nil, .sad, .normal, nil]
    }

    var body: some View {
        ZStack {
            HomeSceneBackgroundView()
            VStack(alignment: .leading, spacing: 12) {
                header
                timelineSample
            }
            .padding(14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: theme.imageDisplayMode == .carousel ? 332 : 268)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(theme.previewMuted, lineWidth: 0.5)
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("外观预览"))
        .accessibilityValue(Text("展示当前模式、主色、背景纹理和图片展示效果"))
        .accessibilityIdentifier("appearanceThemePreview")
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("时刻")
                .font(.headline.weight(.semibold))
                .foregroundStyle(theme.primaryText)
            Spacer()
            Circle()
                .fill(theme.accent)
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.onAccentText)
                )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(theme.sheetPanelBackground)
        )
    }

    private var timelineSample: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 6) {
                MoodNodeView(mood: .normal, diameter: 13)
                Rectangle()
                    .fill(theme.timelineRail)
                    .frame(width: 2, height: 92)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(theme.heatmapEmptyCell)
                    .frame(width: 13, height: 13)
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 10) {
                BubbleCardView(
                    title: "今天的心情",
                    bodyText: "记录当下状态",
                    tagNames: [],
                    placeholderImageHexColors: [0xB678F5, 0x15BEB4, 0xB17521],
                    tailGeometry: BubbleTailGeometry(size: .zero, horizontalOffset: 0)
                )
                heatmapSample
            }
        }
    }

    private var heatmapSample: some View {
        HStack(spacing: 4) {
            ForEach(Array(Self.heatmapPreviewMoods.enumerated()), id: \.offset) { _, mood in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(mood.map { theme.moodColor($0) } ?? theme.heatmapEmptyCell)
                    .frame(width: 13, height: 13)
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppearanceThemeView()
    }
    .environment(ThemeManager())
}
