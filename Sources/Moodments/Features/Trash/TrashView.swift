import SwiftData
import SwiftUI

/// 垃圾箱（见 `docs/design/04-screen-specs.md` §4.14）：已软删除的 Moment 列表，按
/// `deletedAt` 倒序排列；样式沿用时间轴气泡卡片范式的精简版（仅标题+日期）。设置栈内
/// `NavigationLink` push（08-architecture.md §2.2）。
///
/// 右滑（leading）恢复、左滑（trailing）彻底删除——彻底删除不可逆，须 `.alert` 二次确认
/// （与首页删除「无需确认」形成对比，因垃圾箱是最后一道安全网，见公理3「删除是生命周期」）。
struct TrashView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(\.modelContext) private var modelContext
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(SyncStatusService.self) private var syncStatusService
    @Environment(\.localBackupCoordinator) private var localBackupCoordinator

    @State private var items: [MomentSnapshot] = []
    @State private var isLoaded = false
    @State private var purgeTarget: MomentSnapshot?

    var body: some View {
        Group {
            if isLoaded && items.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(items) { item in
                        row(for: item)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(
                                EdgeInsets(
                                    top: TaskSurfaceMetrics.listRowVerticalInset,
                                    leading: TaskSurfaceMetrics.pageHorizontalInset,
                                    bottom: TaskSurfaceMetrics.listRowVerticalInset,
                                    trailing: TaskSurfaceMetrics.pageHorizontalInset
                                )
                            )
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    handleRestore(item)
                                } label: {
                                    Label("恢复", systemImage: "arrow.uturn.left")
                                }
                                .tint(theme.accent)
                                .accessibilityIdentifier("trashRestoreButton-\(item.id.uuidString)")
                            }
                            .destructiveSwipeAction(
                                title: "彻底删除",
                                accessibilityIdentifier: "trashPurgeButton-\(item.id.uuidString)"
                            ) {
                                purgeTarget = item
                            }
                            .accessibilityAction(named: Text("恢复")) { handleRestore(item) }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .taskListContentFrame()
            }
        }
        .background(theme.sheetBackground.ignoresSafeArea())
        .settingsDetailNavigationChrome("垃圾箱")
        .themedTaskContainer(theme)
        .task { await reload() }
        .alert(
            "彻底删除？",
            isPresented: Binding(get: { purgeTarget != nil }, set: { if !$0 { purgeTarget = nil } })
        ) {
            Button("彻底删除", role: .destructive) {
                if let target = purgeTarget { handlePurge(target) }
            }
            Button("取消", role: .cancel) { purgeTarget = nil }
        } message: {
            Text("彻底删除后无法恢复。")
        }
    }

    private var emptyState: some View {
        Text("垃圾箱是空的")
            .font(AppTypography.body)
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("trashEmptyState")
    }

    private func row(for item: MomentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title.isEmpty ? "（无标题）" : item.title)
                .font(AppTypography.cardTitle)
                .foregroundStyle(theme.primaryText)
                .lineLimit(1)
            Text(Self.dateFormatter.string(from: item.occurredAt))
                .font(AppTypography.caption)
                .foregroundStyle(theme.secondaryText)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous).fill(theme.sheetPanelBackground)
        )
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("trashRow-\(item.id.uuidString)")
    }

    private func reload() async {
        do {
            items = try await MomentRepository(modelContainer: modelContext.container).fetchTrash()
        } catch {
            await errorPresenter.report(message: "垃圾箱列表加载失败，请稍后重试。", underlying: error)
        }
        isLoaded = true
    }

    /// 恢复失败不在本地假装已恢复——从仓库真相源 `reload`，让列表反映实际持久化状态
    /// （见阶段6计划决策3：可恢复写失败改走统一错误通道，失败不伪造成功）。
    private func handleRestore(_ item: MomentSnapshot) {
        Task {
            do {
                try await mutationService.restoreMoment(id: item.id)
                await reload()
            } catch LocalLibraryMutationError.mutationSafetyPointFailed(let underlying) {
                await errorPresenter.report(
                    message: "创建操作前安全备份失败，请稍后重试。",
                    underlying: underlying
                )
                await reload()
            } catch {
                await errorPresenter.report(message: "恢复失败，请稍后重试。", underlying: error)
                await reload()
            }
        }
    }

    /// 彻底删除：物理移除 + 释放额度（仓库层）+ 失效该 Moment 全部图片的缩略图缓存
    /// （见 07-data-persistence.md §5：Moment 彻底删除时同步清理其缩略图）。失败同样从仓库
    /// 真相源 `reload`，不假装已删除。
    private func handlePurge(_ item: MomentSnapshot) {
        Task {
            do {
                try await mutationService.purgeMoment(id: item.id, imageIDs: item.imageIDs)
                await reload()
            } catch LocalLibraryMutationError.mutationSafetyPointFailed(let underlying) {
                await errorPresenter.report(
                    message: "创建操作前安全备份失败，请稍后重试。",
                    underlying: underlying
                )
                await reload()
            } catch {
                await errorPresenter.report(message: "彻底删除失败，请稍后重试。", underlying: error)
                await reload()
            }
        }
    }

    private var mutationService: LocalLibraryMutationService {
        LocalLibraryMutationService(
            modelContainer: modelContext.container,
            localBackupCoordinator: localBackupCoordinator,
            syncStatusService: syncStatusService,
            errorPresenter: errorPresenter
        )
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日 HH:mm"
        return formatter
    }()
}
