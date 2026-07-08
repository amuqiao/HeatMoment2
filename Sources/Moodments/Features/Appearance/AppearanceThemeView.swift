import PhotosUI
import SwiftUI

private enum BackgroundImageLoadError: Error {
    case emptyData
}

/// 外观主题子页（见 `docs/design/04-screen-specs.md` §4.15、05-design-system.md §5.3/§5.7）：
/// 模式 / 颜色（主色）/ 网格（背景纹理）/ 图片（图片展示）4 个分组，**乐观更新即时生效**。
///
/// 本页是设置任务容器，不是首页画布：页面骨架使用任务容器 token；每个选项内部的小缩略图
/// 只表达该设置轴的结果预览，避免顶部大预览与下面的设置项争夺层级。
struct AppearanceThemeView: View {
    @Environment(ThemeManager.self) private var theme
    @State private var customBackgroundPickerItem: PhotosPickerItem?

    var body: some View {
        TaskPageScrollView {
            notices
            modeSection
            accentSection
            textureSection
            imageDisplaySection
        }
        .settingsDetailNavigationChrome("外观主题")
        .themedTaskContainer(theme)
        .onChange(of: customBackgroundPickerItem) { _, newItem in
            guard let newItem else { return }
            Task {
                await importCustomBackgroundImage(from: newItem)
                customBackgroundPickerItem = nil
            }
        }
    }

    @ViewBuilder
    private var notices: some View {
        if theme.correctedPreferenceCount > 0 {
            AppearanceInlineNotice(
                text: "已修正 \(theme.correctedPreferenceCount) 项本地偏好配置",
                identifier: "appearanceCorrectedNotice",
                color: theme.accent
            )
        }
        if theme.appearanceSaveFailed {
            AppearanceInlineNotice(
                text: "外观设置保存失败，请稍后重试",
                identifier: "appearanceSaveFailedNotice",
                color: theme.danger
            )
        }
        if theme.customBackgroundImageRecovered {
            AppearanceInlineNotice(
                text: "自定义背景图片不可用，已恢复默认背景",
                identifier: "customBackgroundImageRecoveredNotice",
                color: theme.danger
            )
        }
        if theme.photoDisplaySaveFailed {
            AppearanceInlineNotice(
                text: "照片显示设置保存失败，请稍后重试",
                identifier: "photoDisplaySaveFailedNotice",
                color: theme.danger
            )
        }
    }

    private var modeSection: some View {
        TaskSurfaceSection(title: "模式", accessibilityIdentifier: "appearanceModeSection") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 130), spacing: 28)],
                spacing: 18
            ) {
                AppearanceModeOptionCard(
                    mode: .dark,
                    title: "暗色模式",
                    texture: theme.backgroundTexture,
                    customImageURL: theme.customBackgroundImageURL,
                    isSelected: theme.mode == .dark,
                    identifier: "appearanceModeOption-dark"
                ) {
                    theme.setMode(.dark)
                }
                AppearanceModeOptionCard(
                    mode: .light,
                    title: "亮色模式",
                    texture: theme.backgroundTexture,
                    customImageURL: theme.customBackgroundImageURL,
                    isSelected: theme.mode == .light,
                    identifier: "appearanceModeOption-light"
                ) {
                    theme.setMode(.light)
                }
            }
        }
    }

    private var accentSection: some View {
        TaskSurfaceSection(title: "颜色", accessibilityIdentifier: "appearanceAccentSection") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 44), spacing: 8)],
                spacing: 0
            ) {
                ForEach(AccentColorOption.allCases) { option in
                    AppearanceAccentSwatchButton(
                        option: option,
                        isSelected: theme.accentColor == option
                    ) {
                        theme.setAccentColor(option)
                    }
                }
            }
        }
    }

    private var textureSection: some View {
        let isCustomImageSelected = theme.backgroundTexture == .customImage
        let customImageURL = theme.customBackgroundImageURL

        return TaskSurfaceSection(
            title: "网格",
            accessibilityIdentifier: "appearanceTextureSection"
        ) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 68), spacing: 12)],
                spacing: 14
            ) {
                AppearanceTextureOptionCard(
                    texture: .grid,
                    title: "网格",
                    isSelected: theme.backgroundTexture == .grid,
                    identifier: "appearanceTextureOption-grid"
                ) {
                    theme.setBackgroundTexture(.grid)
                }
                AppearanceTextureOptionCard(
                    texture: .dot,
                    title: "点阵",
                    isSelected: theme.backgroundTexture == .dot,
                    identifier: "appearanceTextureOption-dot"
                ) {
                    theme.setBackgroundTexture(.dot)
                }
                AppearanceTextureOptionCard(
                    texture: .none,
                    title: "无",
                    isSelected: theme.backgroundTexture == .none,
                    identifier: "appearanceTextureOption-none"
                ) {
                    theme.setBackgroundTexture(.none)
                }
                PhotosPicker(selection: $customBackgroundPickerItem, matching: .images) {
                    AppearanceTextureOptionLabel(
                        texture: .customImage,
                        title: "自定义",
                        isSelected: isCustomImageSelected,
                        customImageURL: customImageURL
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("appearanceTextureOption-customImage")
                .accessibilityLabel(Text("背景纹理：自定义图片"))
                .accessibilityAddTraits(isCustomImageSelected ? [.isSelected] : [])
            }

            #if DEBUG
                if UITestSupport.wantsBackgroundImageInjectionHook {
                    Button {
                        Task {
                            await theme.setCustomBackgroundImageData(
                                UITestSupport.makeSyntheticBackgroundImageData()
                            )
                        }
                    } label: {
                        Text("注入测试背景图")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(theme.selectionFill)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("appearanceCustomBackgroundInjectButton")
                }
            #endif
        }
    }

    private var imageDisplaySection: some View {
        TaskSurfaceSection(title: "图片", accessibilityIdentifier: "appearanceImageDisplaySection") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 138), spacing: 18)],
                spacing: 18
            ) {
                AppearanceImageDisplayOptionCard(
                    mode: .scroll,
                    title: "滚动",
                    isSelected: theme.imageDisplayMode == .scroll,
                    identifier: "appearanceImageModeOption-scroll"
                ) {
                    theme.setImageDisplayMode(.scroll)
                }
                AppearanceImageDisplayOptionCard(
                    mode: .carousel,
                    title: "轮播",
                    isSelected: theme.imageDisplayMode == .carousel,
                    identifier: "appearanceImageModeOption-carousel"
                ) {
                    theme.setImageDisplayMode(.carousel)
                }
            }
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
