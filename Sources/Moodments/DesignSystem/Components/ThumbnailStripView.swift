import SwiftData
import SwiftUI
import UIKit

/// 横排缩略图（见 `docs/design/05-design-system.md` §5.5/§5.7、07 §5）：经 `ThumbnailCache`
/// 按需加载——命中缓存直接展示，未命中才向仓库现场取原图生成并回写缓存。时间轴气泡与预览
/// 照片区共用同一组件（见阶段 4 计划）。
///
/// `onTapImage` 非 `nil` 时，点击某张缩略图回调其下标（供预览照片区进入 `ImageViewerView`）；
/// 时间轴气泡整行已有独立的点击语义（打开预览阅读卡片），不传该回调，避免手势冲突
/// （见 `BubbleCardView` 调用处）。
struct ThumbnailStripView: View {
    let imageIDs: [UUID]
    var onTapImage: ((Int) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var thumbnailsByID: [UUID: Data] = [:]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(imageIDs.enumerated()), id: \.element) { index, imageID in
                thumbnail(for: imageID)
                    .onTapGesture { onTapImage?(index) }
                    .accessibilityLabel(Text("照片，第\(index + 1)张，共\(imageIDs.count)张"))
                    .accessibilityIdentifier("thumbnailStripImage-\(imageID.uuidString)")
            }
        }
        .task(id: imageIDs) {
            await loadThumbnails()
        }
    }

    @ViewBuilder
    private func thumbnail(for imageID: UUID) -> some View {
        if let data = thumbnailsByID[imageID], let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.gray.opacity(0.15))
                .frame(width: 72, height: 72)
        }
    }

    /// 逐张经 `ThumbnailCache` 取图：命中缓存零 IO，未命中才 `await` 向仓库取原图现场生成
    /// （见 `ThumbnailCache.thumbnail(for:maxDimension:provideOriginal:)` 的 async 重载）。
    private func loadThumbnails() async {
        let repository = MomentRepository(modelContainer: modelContext.container)
        for imageID in imageIDs where thumbnailsByID[imageID] == nil {
            do {
                let data = try await ThumbnailCache.shared.thumbnail(for: imageID) {
                    try await repository.imageData(imageID: imageID)
                }
                thumbnailsByID[imageID] = data
            } catch {
                assertionFailure("缩略图加载失败 imageID=\(imageID)：\(error)")
            }
        }
    }
}
