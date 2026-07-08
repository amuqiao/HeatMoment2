import SwiftData
import SwiftUI
import UIKit

/// 单条时刻预览：弹出的阅读卡片（进任务卡片栈，非 push，见 `docs/design/04-screen-specs.md` §4.9、
/// `14-design-decisions.md` ADR-007）。由 `AppRouter.rootSheet` 的 `.preview(Moment.ID)` 驱动
/// （第一层）；编辑入口、图片查看器均为**本视图局部**的第二层浮层，不改 `router.rootSheet`
/// （见 08-architecture.md §2.2 层叠协作说明）。
struct MomentPreviewView: View {
    let momentID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(SubscriptionService.self) private var subscriptionService

    @Query private var moments: [Moment]
    @State private var editorPresentation: EditorPresentation?
    @State private var viewerContext: ViewerContext?
    @AccessibilityFocusState private var isTitleFocused: Bool

    init(momentID: UUID) {
        self.momentID = momentID
        _moments = Query(filter: #Predicate<Moment> { $0.id == momentID })
    }

    var body: some View {
        NavigationStack {
            Group {
                if let moment = moments.first {
                    content(for: moment)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(theme.sheetBackground.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("momentPreviewCloseButton")
                }
                if let moment = moments.first {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("编辑") {
                            editorPresentation = EditorPresentation(mode: .edit(moment.id))
                        }
                        .accessibilityIdentifier("momentPreviewEditButton")
                    }
                }
            }
        }
        .themedTaskContainer(theme)
        // 阅读卡片对底层已下沉的时间轴做 VoiceOver 模态隔离，防焦点穿透（见 04 §4.9）。
        .accessibilityAddTraits(.isModal)
        .sheet(item: $editorPresentation) { presentation in
            MomentEditorView(
                mode: presentation.mode, modelContainer: modelContext.container,
                subscriptionService: subscriptionService
            )
        }
        .fullScreenCover(item: $viewerContext) { context in
            ImageViewerView(momentID: momentID, startIndex: context.startIndex)
        }
    }

    // MARK: - 内容（见 04-screen-specs.md §4.9：顶部心情/日期/编辑入口；正文区标题/标签/照片/正文）

    private func content(for moment: Moment) -> some View {
        TaskPageScrollView(spacing: 20, accessibilityIdentifier: "momentPreviewCard") {
            header(for: moment)

            if !moment.title.isEmpty {
                Text(moment.title)
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
            }

            let tagNames = moment.tags.map(\.name)
            if !tagNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tagNames, id: \.self) { name in
                        TagChipView(name: name)
                    }
                }
            }

            let orderedImages = orderedImages(for: moment)
            let imageIDs = orderedImages.map(\.id)
            if !imageIDs.isEmpty {
                ThumbnailStripView(
                    imageIDs: imageIDs,
                    displayMode: .scroll,
                    usesMomentPhotoRailLayout: true,
                    preferredSizesByID: preferredSizesByID(for: orderedImages)
                ) { index in
                    viewerContext = ViewerContext(startIndex: index)
                }
            }

            if !moment.bodyText.isEmpty {
                Text(moment.bodyText)
                    .font(AppTypography.body)
                    .foregroundStyle(theme.secondaryText)
            }
        }
        // 阅读卡片弹出完成后，VoiceOver 焦点移到标题，避免停留在已下沉的时间轴卡片上
        // （见 04 §4.9 无障碍要求）；若标题为空（无标题时刻）则不移动焦点，交由系统默认行为。
        .onAppear {
            if !moment.title.isEmpty {
                isTitleFocused = true
            }
        }
    }

    private func header(for moment: Moment) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                MoodNodeView(mood: moment.mood, diameter: 14)
                Text("\(moment.mood.emoji) \(moment.mood.displayName)")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
            }
            Spacer()
            Text(Self.dateFormatter.string(from: moment.occurredAt))
                .font(AppTypography.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    /// 按 `sortIndex` 有序的图片列表（见 07-data-persistence.md §5）。
    private func orderedImages(for moment: Moment) -> [MomentImage] {
        moment.images.sorted { $0.sortIndex < $1.sortIndex }
    }

    private func preferredSizesByID(for images: [MomentImage]) -> [UUID: CGSize] {
        Dictionary(
            uniqueKeysWithValues: images.map { image in
                let size =
                    UIImage(data: image.imageData).map {
                        MomentPhotoRailLayout.itemSize(for: $0.size)
                    } ?? MomentPhotoRailLayout.fallbackItemSize
                return (image.id, size)
            }
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}

/// 预览内「编辑」的第二层任务卡片呈现上下文（`.sheet(item:)` 驱动，不进 `AppRouter`，
/// 见 08-architecture.md §2.2 第二层）。
private struct EditorPresentation: Identifiable {
    let mode: EditorMode
    var id: String { mode.id }
}

/// 预览内「点图片」的第二层沉浸全屏呈现上下文（`.fullScreenCover(item:)` 驱动，本视图局部持有，
/// 不进 `router.fullScreenCover`——避免 sheet 之上从根 present 冲突，见阶段 4 计划决策B）。
private struct ViewerContext: Identifiable {
    let id = UUID()
    let startIndex: Int
}
