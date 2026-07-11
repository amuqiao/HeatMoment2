import SwiftUI

/// 上下文标记横条（见 `docs/product-mental-model.md`「上下文标记」对象、
/// `docs/design/04-screen-specs.md` §4.1、`docs/design/03-user-flows.md` §3.3）：
/// 告诉用户「现在看的是完整记录，还是某个筛选/某个时间位置」——筛选标记（`#标签`/情绪）
/// 与时间标记（年/月/日）**可同时存在但含义不同**：移除筛选标记改变「看哪些记录」
/// （清 `TimelineModel.activeFilter` 某一维度）；移除时间标记改变「是否停在某个时间位置」
/// （清 `TimelineModel.heatmapFocusDate`，二者互不影响，见公理2）。时间标记可表达日锚点或月锚点。
///
/// 固定在 topBar 之下常驻（由 `TimelineHomeView` 通过 `.safeAreaInset(edge: .top)` 与
/// topBar 一起放入同一个不随列表滚走的容器）。
struct TimelineContextMarkerBar: View {
    let layout: TimelineHomeLayout

    @Environment(TimelineModel.self) private var timelineModel
    @Environment(ThemeManager.self) private var theme
    @Environment(CanonicalLibraryService.self) private var canonicalService

    @State private var tags: [TagSnapshot] = []

    private var tagNamesByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
    }

    var body: some View {
        @Bindable var timelineModel = timelineModel

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let filter = timelineModel.activeFilter {
                    // 防御性跳过陈旧 id（阶段6）：正常路径下标签删除会同步调用
                    // `TimelineModel.discardFilterTag` 清理 `activeFilter`，此处的 `tagNamesByID`
                    // 缺失只应在极端时序下出现（如清理动作与本视图重渲染之间的一帧），跳过渲染
                    // 该标记，不展示「#」空壳、也不让它可点，避免中间态泄漏到用户界面。
                    ForEach(Array(filter.tagIDs).sorted(), id: \.self) { tagID in
                        if let tagName = tagNamesByID[tagID] {
                            marker(
                                text: "#\(tagName)",
                                identifier: "contextMarkerTag-\(tagID.uuidString)"
                            ) {
                                var updated = filter
                                updated.tagIDs.remove(tagID)
                                timelineModel.activeFilter = updated.isEmpty ? nil : updated
                            }
                        }
                    }

                    if let mood = filter.mood {
                        marker(
                            text: "\(mood.emoji) \(mood.displayName)",
                            identifier: "contextMarkerMood"
                        ) {
                            var updated = filter
                            updated.mood = nil
                            timelineModel.activeFilter = updated.isEmpty ? nil : updated
                        }
                    }
                }

                if let focusDate = timelineModel.heatmapFocusDate {
                    marker(
                        text: timeMarkerText(for: focusDate),
                        identifier: "contextMarkerTime"
                    ) {
                        timelineModel.clearHeatmapAnchor()
                    }
                }
            }
            .padding(.horizontal, layout.topChromeHorizontalPadding)
            .padding(.vertical, layout.topChromeVerticalPadding)
        }
        .task(id: canonicalService.changeToken) {
            do {
                tags = try await canonicalService.fetchFilterTags()
            } catch {
                assertionFailure("上下文标记标签加载失败：\(error)")
            }
        }
    }

    private func marker(
        text: String,
        identifier: String,
        onRemove: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(theme.primaryText)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(theme.secondaryText)
            }
            .accessibilityLabel(Text("移除条件 \(text)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(theme.chipFill))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private func timeMarkerText(for date: Date) -> String {
        switch timelineModel.heatmapAnchorGranularity {
        case .month:
            Self.monthMarkerFormatter.string(from: date)
        case .day, .none:
            Self.dayMarkerFormatter.string(from: date)
        }
    }

    private static let dayMarkerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()

    private static let monthMarkerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月"
        return formatter
    }()
}

#Preview {
    let model = TimelineModel()
    model.activeFilter = FilterCondition(mood: .happy)
    model.setHeatmapAnchor(.now, granularity: .month)
    return TimelineContextMarkerBar(layout: .standard)
        .environment(ThemeManager())
        .environment(model)
        .environment(CanonicalLibraryService.makeInMemoryForPreview())
}
