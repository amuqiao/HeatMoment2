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
            }
            if theme.appearanceSaveFailed {
                Section {
                    inlineNotice(
                        text: "外观设置保存失败，请稍后重试",
                        identifier: "appearanceSaveFailedNotice",
                        color: theme.danger
                    )
                }
            }
            if theme.customBackgroundImageRecovered {
                Section {
                    inlineNotice(
                        text: "自定义背景图片不可用，已恢复默认背景",
                        identifier: "customBackgroundImageRecoveredNotice",
                        color: theme.danger
                    )
                }
            }
            if theme.photoDisplaySaveFailed {
                Section {
                    inlineNotice(
                        text: "照片显示设置保存失败，请稍后重试",
                        identifier: "photoDisplaySaveFailedNotice",
                        color: theme.danger
                    )
                }
            }

            Section("模式") {
                modeRow(.dark, label: "暗色")
                modeRow(.light, label: "亮色")
            }

            Section("颜色") {
                ForEach(AccentColorOption.allCases) { option in
                    accentRow(option)
                }
            }

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

            Section("图片") {
                imageModeRow(.scroll, label: "滚动")
                imageModeRow(.carousel, label: "轮播")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(theme.canvasBackground.ignoresSafeArea())
        .navigationTitle("主题颜色")
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
                    .fill(option.color(for: theme.mode))
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

#Preview {
    NavigationStack {
        AppearanceThemeView()
    }
    .environment(ThemeManager())
}
