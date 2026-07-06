import SwiftData
import SwiftUI

/// 上下文标记横条（见 `docs/product-mental-model.md`「上下文标记」对象、
/// `docs/design/04-screen-specs.md` §4.1、`docs/design/03-user-flows.md` §3.3）：
/// 告诉用户「现在看的是完整记录，还是某个筛选/某个时间位置」——筛选标记（`#标签`/情绪）
/// 与时间标记（年/月/日）**可同时存在但含义不同**：移除筛选标记改变「看哪些记录」
/// （清 `TimelineModel.activeFilter` 某一维度）；移除时间标记改变「是否停在某个时间位置」
/// （清 `TimelineModel.heatmapFocusDate`，二者互不影响，见公理2）。
///
/// 固定在 topBar 之下常驻（由 `TimelineHomeView` 通过 `.safeAreaInset(edge: .top)` 与
/// topBar 一起放入同一个不随列表滚走的容器）。
struct TimelineContextMarkerBar: View {
    @Environment(TimelineModel.self) private var timelineModel
    @Environment(ThemeManager.self) private var theme

    @Query(sort: \Tag.createdAt) private var tags: [Tag]

    private var tagNamesByID: [UUID: String] {
        Dictionary(uniqueKeysWithValues: tags.map { ($0.id, $0.name) })
    }

    var body: some View {
        @Bindable var timelineModel = timelineModel

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let filter = timelineModel.activeFilter {
                    ForEach(Array(filter.tagIDs).sorted(), id: \.self) { tagID in
                        marker(
                            text: "#\(tagNamesByID[tagID] ?? "")",
                            identifier: "contextMarkerTag-\(tagID.uuidString)"
                        ) {
                            var updated = filter
                            updated.tagIDs.remove(tagID)
                            timelineModel.activeFilter = updated.isEmpty ? nil : updated
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
                        text: Self.timeMarkerFormatter.string(from: focusDate),
                        identifier: "contextMarkerTime"
                    ) {
                        timelineModel.heatmapFocusDate = nil
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
        }
    }

    private func marker(text: String, identifier: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(text)
                .font(AppTypography.caption)
                .foregroundStyle(theme.primaryText)
            Button {
                onRemove()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(SemanticColor.secondaryText)
            }
            .accessibilityLabel(Text("移除条件 \(text)"))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(theme.chipFill))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private static let timeMarkerFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        return formatter
    }()
}

#Preview {
    let model = TimelineModel()
    model.activeFilter = FilterCondition(mood: .happy)
    model.heatmapFocusDate = .now
    return TimelineContextMarkerBar()
        .environment(ThemeManager())
        .environment(model)
        // swiftlint:disable:next force_try
        .modelContainer(try! ModelContainerConfig.makeInMemoryContainer())
}
