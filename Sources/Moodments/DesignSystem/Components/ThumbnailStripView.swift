import SwiftData
import SwiftUI
import UIKit

/// 横排缩略图（见 `docs/design/05-design-system.md` §5.5/§5.7、07 §5）：经 `ThumbnailCache`
/// 按需加载——命中缓存直接展示，未命中才向仓库现场取原图生成并回写缓存。时间轴气泡与预览
/// 照片区共用同一组件（见阶段 4 计划）。
///
/// `onTapImage` 非 `nil` 时，点击某张缩略图回调其下标（供预览照片区进入 `ImageViewerView`）；
/// 时间轴气泡整行已有独立的点击和左滑删除语义，调用处会让图片区保持 hit testing，
/// 避免图片上的横向滚动 / 轮播切换被误解释成 `List` 行级删除。
struct ThumbnailStripView: View {
    let imageIDs: [UUID]
    var displayMode: ImageDisplayMode = .scroll
    var allowsImageInteraction = true
    var onTapImage: ((Int) -> Void)?

    @Environment(\.modelContext) private var modelContext
    @State private var thumbnailsByID: [UUID: Data] = [:]

    var body: some View {
        imageGallery
            .allowsHitTesting(allowsImageInteraction)
            .task(id: imageIDs) {
                await loadThumbnails()
            }
    }

    @ViewBuilder
    private var imageGallery: some View {
        switch displayMode {
        case .scroll:
            ScrollView(.horizontal) {
                LazyHStack(spacing: MomentCardLayout.thumbnailSpacing) {
                    ForEach(Array(imageIDs.enumerated()), id: \.element) { index, imageID in
                        thumbnail(for: imageID)
                            .frame(
                                width: MomentCardLayout.thumbnailSize.width,
                                height: MomentCardLayout.thumbnailSize.height
                            )
                            .onTapGesture { onTapImage?(index) }
                            .accessibilityLabel(Text("照片，第\(index + 1)张，共\(imageIDs.count)张"))
                            .accessibilityIdentifier("thumbnailStripImage-\(imageID.uuidString)")
                    }
                }
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("thumbnailStrip")
            .frame(height: MomentCardLayout.imageSectionHeight(for: .scroll))
            .frame(maxWidth: .infinity, alignment: .leading)
        case .carousel:
            TabView {
                ForEach(Array(imageIDs.enumerated()), id: \.element) { index, imageID in
                    thumbnail(for: imageID)
                        .frame(maxWidth: .infinity)
                        .frame(height: MomentCardLayout.carouselHeight)
                        .onTapGesture { onTapImage?(index) }
                        .accessibilityLabel(Text("照片，第\(index + 1)张，共\(imageIDs.count)张"))
                        .accessibilityIdentifier("thumbnailStripImage-\(imageID.uuidString)")
                }
            }
            .tabViewStyle(.page(indexDisplayMode: imageIDs.count > 1 ? .automatic : .never))
            .accessibilityIdentifier("thumbnailStrip")
            .frame(height: MomentCardLayout.imageSectionHeight(for: .carousel))
        }
    }

    @ViewBuilder
    private func thumbnail(for imageID: UUID) -> some View {
        if let data = thumbnailsByID[imageID] {
            if let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: MomentCardLayout.thumbnailCornerRadius,
                            style: .continuous
                        )
                    )
            } else {
                // 数据已加载却解码失败：缩略图 JPEG 由本 App 生成，失败即数据损坏，debug 暴露。
                corruptedThumbnailPlaceholder(imageID: imageID)
            }
        } else {
            placeholder  // 尚未加载完成（正常态，非错误）
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: MomentCardLayout.thumbnailCornerRadius, style: .continuous)
            .fill(Color.gray.opacity(0.15))
    }

    private func corruptedThumbnailPlaceholder(imageID: UUID) -> some View {
        assertionFailure("缩略图解码失败 imageID=\(imageID)")
        return placeholder
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
