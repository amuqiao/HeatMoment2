import SwiftUI
import UIKit

/// 单条时刻预览：弹出的阅读卡片（进任务卡片栈，非 push，见 `docs/current/implementation-truth.md` §4.9、
/// `docs/current/implementation-truth.md` ADR-007）。由 `AppRouter.rootSheet` 的 `.preview(Moment.ID)` 驱动
/// （第一层）；编辑入口、图片查看器均为**本视图局部**的第二层浮层，不改 `router.rootSheet`
/// （见 docs/current/implementation-truth.md §2.2 层叠协作说明）。
struct MomentPreviewView: View {
    let momentID: UUID

    @Environment(\.dismiss) private var dismiss
    @Environment(ThemeManager.self) private var theme
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SubscriptionService.self) private var subscriptionService

    @State private var previewData: CanonicalMomentPreviewData?
    @State private var editorPresentation: EditorPresentation?
    @State private var viewerContext: ViewerContext?
    @AccessibilityFocusState private var isTitleFocused: Bool

    init(momentID: UUID) {
        self.momentID = momentID
    }

    var body: some View {
        AppSheetScaffold {
            Group {
                if let previewData {
                    content(for: previewData)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .appSheetChrome(
                cancellation: AppSheetAction(
                    "关闭",
                    accessibilityIdentifier: "momentPreviewCloseButton"
                ) {
                    dismiss()
                },
                confirmation: previewEditAction
            )
        }
        // 阅读卡片对底层已下沉的时间轴做 VoiceOver 模态隔离，防焦点穿透（见 docs/current/implementation-truth.md §4.9）。
        .accessibilityAddTraits(.isModal)
        .sheet(item: $editorPresentation) { presentation in
            MomentEditorView(
                mode: presentation.mode, canonicalService: canonicalService,
                subscriptionService: subscriptionService
            )
        }
        .fullScreenCover(item: $viewerContext) { context in
            ImageViewerView(momentID: momentID, startIndex: context.startIndex)
        }
        .userFacingErrorAlert(errorPresenter)
        .task(id: canonicalService.changeToken) {
            await loadPreview()
        }
    }

    private var previewEditAction: AppSheetAction? {
        guard let record = previewData?.record else { return nil }
        return AppSheetAction(
            "编辑",
            accessibilityIdentifier: "momentPreviewEditButton"
        ) {
            editorPresentation = EditorPresentation(mode: .edit(record.id))
        }
    }

    // MARK: - 内容（见 docs/current/implementation-truth.md §4.9：顶部心情/日期/编辑入口；正文区标题/标签/照片/正文）

    private func content(for previewData: CanonicalMomentPreviewData) -> some View {
        let moment = previewData.record
        return TaskPageScrollView(spacing: 20, accessibilityIdentifier: "momentPreviewCard") {
            header(for: moment)

            if !moment.title.isEmpty {
                Text(moment.title)
                    .font(AppTypography.pageTitle)
                    .foregroundStyle(theme.primaryText)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($isTitleFocused)
            }

            let tagNames = previewData.tagNames
            if !tagNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tagNames, id: \.self) { name in
                        TagChipView(name: name)
                    }
                }
            }

            let imageIDs = previewData.imageDatas.map(\.id)
            if !imageIDs.isEmpty {
                ThumbnailStripView(
                    imageIDs: imageIDs,
                    displayMode: .scroll,
                    usesMomentPhotoRailLayout: true,
                    preferredSizesByID: previewData.preferredSizesByID
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
        // （见 docs/current/implementation-truth.md §4.9 无障碍要求）；若标题为空（无标题时刻）则不移动焦点，交由系统默认行为。
        .onAppear {
            if !moment.title.isEmpty {
                isTitleFocused = true
            }
        }
    }

    private func header(for moment: CanonicalMomentRecord) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                MoodNodeView(
                    mood: moment.mood,
                    diameter: 14,
                    style: TimelineMoodNodeStyle(innerDiameterRatio: 0.5, outerOpacity: 0.38)
                )
                Text("\(moment.mood.emoji) \(moment.mood.displayName)")
                    .font(AppTypography.body)
                    .foregroundStyle(theme.primaryText)
            }
            Spacer()
            Text(MomentPreviewDateFormatters.occurredAtText(for: moment.occurredAt))
                .font(AppTypography.caption)
                .foregroundStyle(theme.secondaryText)
        }
    }

    private func loadPreview() async {
        do {
            previewData = try await canonicalService.fetchPreviewData(id: momentID)
        } catch {
            errorPresenter.report(message: "加载时刻失败，请稍后重试。", underlying: error)
        }
    }

}

enum MomentPreviewDateFormatters {
    static func occurredAtText(for date: Date, timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.timeZone = timeZone
        formatter.dateFormat = "M月d日 E HH:mm"
        return formatter.string(from: date)
    }
}

/// 预览内「编辑」的第二层任务卡片呈现上下文（`.sheet(item:)` 驱动，不进 `AppRouter`，
/// 见 docs/current/implementation-truth.md §2.2 第二层）。
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
