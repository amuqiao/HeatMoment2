import SwiftData
import SwiftUI
import UIKit

/// 图片查看器（见 `docs/design/04-screen-specs.md` §4.10、08-architecture.md §2.2）：
/// `.fullScreenCover` 呈现，无层叠语义的沉浸全屏，横向分页浏览一个 Moment 的全部原图 +
/// 捏合/双击缩放 + 关闭。一次性经 `MomentRepository.orderedImageData(momentID:)` 取全量原图
/// （用户已明确要打开查看器，不同于缩略图的懒加载路径，见阶段 4 计划）。
struct ImageViewerView: View {
    let momentID: UUID
    let startIndex: Int

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var theme
    @State private var currentIndex: Int
    @State private var images: [MomentImageData] = []
    @State private var isLoaded = false

    init(momentID: UUID, startIndex: Int) {
        self.momentID = momentID
        self.startIndex = startIndex
        _currentIndex = State(initialValue: startIndex)
    }

    var body: some View {
        ZStack {
            theme.imageViewerBackground.ignoresSafeArea()

            if isLoaded {
                TabView(selection: $currentIndex) {
                    ForEach(Array(images.enumerated()), id: \.element.id) { index, image in
                        pageView(for: image, index: index)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .automatic : .never))
            } else {
                ProgressView().tint(theme.onImageViewerChrome)
            }

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(
                                theme.onImageViewerChrome,
                                theme.imageViewerChromeScrim
                            )
                            .font(.system(size: 30))
                    }
                    .padding()
                    .accessibilityIdentifier("imageViewerCloseButton")
                    .accessibilityLabel(Text("关闭"))
                }
                Spacer()
            }
        }
        .accessibilityIdentifier("imageViewerCover")
        .task {
            await loadImages()
        }
    }

    private func pageView(for image: MomentImageData, index: Int) -> some View {
        Group {
            if let uiImage = UIImage(data: image.data) {
                ZoomableImageView(uiImage: uiImage)
            } else {
                imageDecodeFailureView(imageID: image.id)
            }
        }
        .accessibilityLabel(Text("照片，第\(index + 1)张，共\(images.count)张"))
    }

    private func imageDecodeFailureView(imageID: UUID) -> some View {
        // 原图数据来自自有存储（入库压缩的 JPEG），解码失败即数据损坏，debug 暴露。
        assertionFailure("图片查看器原图解码失败 imageID=\(imageID)")
        return Color.clear
    }

    /// - Note: 不吞错——加载失败按 CLAUDE.md「不擅自添加兜底策略」显式暴露（debug 崩溃、
    ///   release 保留空态而非伪装成功），调用方（预览/根路由）打开本视图前已确认 `momentID` 有效。
    private func loadImages() async {
        do {
            images = try await MomentRepository(modelContainer: modelContext.container)
                .orderedImageData(momentID: momentID)
        } catch {
            assertionFailure("图片查看器取原图失败 momentID=\(momentID)：\(error)")
        }
        isLoaded = true
    }
}

/// 支持捏合缩放 + 双击放大的图片页（见 04-screen-specs.md §4.10）。
private struct ZoomableImageView: View {
    let uiImage: UIImage

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    /// 缩放上界：防止无界放大导致的性能/可用性问题（见 code review）。下界 1（贴合原图）。
    private let maxScale: CGFloat = 4

    var body: some View {
        Image(uiImage: uiImage)
            .resizable()
            .scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in scale = min(maxScale, max(1, lastScale * value)) }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = scale > 1 ? 1 : 2
                    lastScale = scale
                }
            }
    }
}
