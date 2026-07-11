import SwiftUI

/// 标签管理子页（见 `docs/design/04-screen-specs.md` §4.13）：列表 + 右上「+」新建 +
/// 点击进入重命名（复用 `TagCreateSheetView` 的重命名态，预填原名）+ 滑动删除（只解除关联，
/// 不触发垃圾箱生命周期，见公理7「标签是归类不是所有权」）。设置栈内 push（08 §2.2）。
///
/// 删除成功后调用 `TimelineModel.discardFilterTag`，清理筛选态里可能引用该标签的陈旧 id
/// （阶段6计划决策5；`TimelineModel` 由 `RootView` 上提注入，经 `.sheet` 内容默认继承环境
/// 可在此直接读取，见 08-architecture.md §3/§4）。
struct TagManageView: View {
    @Environment(ThemeManager.self) private var theme
    @Environment(ErrorPresenter.self) private var errorPresenter
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(CanonicalLibraryService.self) private var canonicalService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(SyncStatusService.self) private var syncStatusService
    @Environment(\.localBackupCoordinator) private var localBackupCoordinator
    @Environment(\.canonicalRecoveryCoordinator) private var canonicalRecoveryCoordinator

    @State private var tags: [TagSnapshot] = []
    @State private var isLoaded = false
    @State private var editContext: TagEditContext?
    @State private var paywallTrigger: PaywallTrigger?
    @State private var isCheckingCreateQuota = false

    private enum TagEditContext: Identifiable {
        case create
        case rename(TagSnapshot)

        var id: String {
            switch self {
            case .create: "create"
            case let .rename(tag): "rename-\(tag.id.uuidString)"
            }
        }
    }

    var body: some View {
        Group {
            if isLoaded && tags.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(tags) { tag in
                        row(for: tag)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .taskListContentFrame()
            }
        }
        .background(theme.sheetBackground.ignoresSafeArea())
        .settingsDetailNavigationChrome("标签管理")
        .themedTaskContainer(theme)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    handleRequestCreateTag()
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(isCheckingCreateQuota)
                .accessibilityIdentifier("tagManageAddButton")
                .accessibilityLabel(Text("新建标签"))
            }
        }
        .task { await reload() }
        .sheet(item: $editContext) { context in
            switch context {
            case .create:
                TagCreateSheetView { _, _ in
                    Task { await reload() }
                }
            case let .rename(tag):
                TagCreateSheetView(editing: tag) { _, _ in
                    Task { await reload() }
                }
            }
        }
        .sheet(item: $paywallTrigger) { trigger in
            ProPaywallView(trigger: trigger)
        }
    }

    private var emptyState: some View {
        Text("还没有标签")
            .font(AppTypography.body)
            .foregroundStyle(theme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityIdentifier("tagManageEmptyState")
    }

    private func row(for tag: TagSnapshot) -> some View {
        Button {
            editContext = .rename(tag)
        } label: {
            Text("#\(tag.name)")
                .foregroundStyle(theme.primaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(
                        theme.sheetPanelBackground)
                )
                // 见 `MoodPickerView`/`TagPickerView`/`FilterPanelView` 同类注释：不加
                // `contentShape` 时命中区域会退化为文字字形本身的绘制区域，padding/背景色的
                // 空白部分点不中——这里整行都要可点（双击重命名），必须显式声明整个矩形可命中。
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .accessibilityIdentifier("tagManageRow-\(tag.id.uuidString)")
        .accessibilityLabel(Text("#\(tag.name)，双击重命名"))
        .destructiveSwipeAction(
            title: "删除",
            accessibilityIdentifier: "tagManageDeleteButton-\(tag.id.uuidString)",
            accessibilityActionName: "删除标签"
        ) {
            handleDelete(tag)
        }
    }

    private func reload() async {
        do {
            tags = try await canonicalService.fetchFilterTags()
        } catch {
            errorPresenter.report(message: "标签列表加载失败，请稍后重试。", underlying: error)
        }
        isLoaded = true
    }

    /// 新增标签入口统一归属设置页。打开新建卡片前现场重查 Pro 权威状态并经
    /// `QuotaService` 判定；超额时打开 Paywall，不进入新建标签表单。
    private func handleRequestCreateTag() {
        guard !isCheckingCreateQuota, editContext == nil, paywallTrigger == nil else { return }
        isCheckingCreateQuota = true
        Task {
            defer { isCheckingCreateQuota = false }
            do {
                let count = try await canonicalService.repository.totalTagCount()
                let isPro = await subscriptionService.currentEntitlementIsPro()
                let quotaService = QuotaService(
                    entitlementProvider: SubscriptionEntitlementProvider(isPro: isPro)
                )
                switch quotaService.checkCanCreateTag(currentTagCount: count) {
                case .allowed:
                    if editContext == nil, paywallTrigger == nil {
                        editContext = .create
                    }
                case .exceeded:
                    if editContext == nil, paywallTrigger == nil {
                        paywallTrigger = .quotaTag
                    }
                }
            } catch {
                errorPresenter.report(message: "标签额度校验失败，请稍后重试。", underlying: error)
            }
        }
    }

    /// 删除只解除该标签与全部时刻的关联（`.nullify`），时刻本身的标题/正文/照片/时间/心情
    /// 全部保留（公理7）；成功后同步清理筛选态里可能引用它的陈旧 id
    /// （`TimelineModel.discardFilterTag`，见类型头部说明）。失败从真相源 `reload`，不在本地
    /// 假装已删除。
    private func handleDelete(_ tag: TagSnapshot) {
        Task {
            do {
                try await mutationService.deleteTag(id: tag.id)
                timelineModel.discardFilterTag(tag.id)
                await reload()
            } catch LocalLibraryMutationError.mutationSafetyPointFailed(let underlying) {
                errorPresenter.report(
                    message: "创建操作前安全备份失败，请稍后重试。",
                    underlying: underlying
                )
                await reload()
            } catch {
                errorPresenter.report(message: "删除标签失败，请稍后重试。", underlying: error)
                await reload()
            }
        }
    }

    private var mutationService: LocalLibraryMutationService {
        LocalLibraryMutationService(
            canonicalService: canonicalService,
            localBackupCoordinator: localBackupCoordinator,
            canonicalRecoveryCoordinator: canonicalRecoveryCoordinator,
            syncStatusService: syncStatusService,
            errorPresenter: errorPresenter
        )
    }
}
