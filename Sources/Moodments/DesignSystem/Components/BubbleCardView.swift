import SwiftUI

/// 气泡时间轴卡片（见 05-design-system.md §5.5）：圆角矩形 + 左侧尾巴，内含标题（单行）、
/// 正文摘要（最多 3 行截断）、图片区（若有）与标签 chip。心情色不用于渲染文字（依 05 §5.10），
/// 卡片内文字统一使用语义文字色。
struct BubbleCardView: View {
    let title: String
    let bodyText: String
    let tagNames: [String]
    /// 占位图片色块（仅供预置引导 Moment 模拟「图片」区，见 05 §5.7）。
    let placeholderImageHexColors: [UInt32]
    /// 真实 Moment 的图片 id（经 `ThumbnailStripView` 按需加载缩略图，见阶段 4 计划）；
    /// 与 `placeholderImageHexColors` 互斥——真实 Moment 用此项，预置引导 Moment 用占位色块。
    var imageIDs: [UUID] = []
    /// 气泡尾巴中心相对卡片顶部的 y 坐标；由时间轴行传入，用来和心情节点中心建立几何绑定。
    var tailCenterY: CGFloat = 30
    /// 气泡尾巴自身的几何参数。时间轴阅读单元会从 `TimelineGeometry` 传入，避免尾巴
    /// 尺寸/偏移和节点/轨道坐标分散维护。
    var tailGeometry: BubbleTailGeometry = .timelineDefault

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            textBlock(for: contentKind)

            if !placeholderImageHexColors.isEmpty {
                PlaceholderImageGalleryView(
                    hexColors: placeholderImageHexColors,
                    displayMode: theme.imageDisplayMode,
                    allowsImageInteraction: MomentCardLayout.timelineImageGalleryAllowsHitTesting
                )
            } else if !imageIDs.isEmpty {
                // 图片区是媒体交互区：横向滚动/轮播优先，不把图片上的左滑解释成删除。
                // 非图片区仍由 `List.swipeActions` 承担系统行级删除。
                ThumbnailStripView(
                    imageIDs: imageIDs,
                    displayMode: theme.imageDisplayMode,
                    allowsImageInteraction: MomentCardLayout.timelineImageGalleryAllowsHitTesting
                )
            }

            if !tagNames.isEmpty {
                HStack(spacing: 6) {
                    ForEach(tagNames, id: \.self) { name in
                        TagChipView(name: name)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.bubbleBackground)
                .overlay(alignment: .topLeading) {
                    BubbleTailShape()
                        .fill(theme.bubbleBackground)
                        .frame(width: tailGeometry.size.width, height: tailGeometry.size.height)
                        .offset(
                            x: tailGeometry.horizontalOffset,
                            y: tailCenterY + tailGeometry.centerYOffset
                        )
                }
        )
    }

    private var hasImages: Bool {
        !placeholderImageHexColors.isEmpty || !imageIDs.isEmpty
    }

    private var contentKind: MomentCardContentKind {
        MomentCardContentKind(title: title, bodyText: bodyText, hasImages: hasImages)
    }

    @ViewBuilder
    private func textBlock(for kind: MomentCardContentKind) -> some View {
        switch kind {
        case .titleOnly:
            titleText
        case .bodyOnly:
            bodyTextView
        case .titleAndBody:
            titleText
            bodyTextView
        case .textWithImages:
            if !title.isEmpty { titleText }
            if !bodyText.isEmpty { bodyTextView }
        case .imagesOnly:
            EmptyView()
        }
    }

    private var titleText: some View {
        Text(title)
            .font(AppTypography.cardTitle)
            .foregroundStyle(theme.bubbleTitleText)
            .lineLimit(1)
    }

    private var bodyTextView: some View {
        Text(bodyText)
            .font(AppTypography.body)
            .foregroundStyle(theme.bubbleBodyText)
            .lineLimit(3)
            .truncationMode(.tail)
    }
}

/// Moment 气泡内容形态。它把“标题/正文/图片”组合显式枚举出来，避免展示层只对
/// 当前 happy path 写死布局，后续支持纯图片或纯正文时破坏时间轴骨架。
enum MomentCardContentKind: Equatable {
    case titleOnly
    case bodyOnly
    case titleAndBody
    case textWithImages
    case imagesOnly

    init(title: String, bodyText: String, hasImages: Bool) {
        let hasTitle = !title.isEmpty
        let hasBody = !bodyText.isEmpty

        switch (hasTitle, hasBody, hasImages) {
        case (true, false, false):
            self = .titleOnly
        case (false, true, false):
            self = .bodyOnly
        case (true, true, false):
            self = .titleAndBody
        case (true, _, true), (false, true, true):
            self = .textWithImages
        case (false, false, true):
            self = .imagesOnly
        case (false, false, false):
            assertionFailure("MomentCardContentKind requires at least one visible content axis")
            self = .bodyOnly
        }
    }
}

/// 首页 Moment 气泡图片区的稳定尺寸合同。
///
/// 图片数量、原图比例、滚动/轮播模式都不能反向撑开气泡宽度；只允许决定图片区高度。
struct MomentCardLayout {
    static let thumbnailSize = CGSize(width: 72, height: 72)
    static let thumbnailSpacing: CGFloat = 8
    static let thumbnailCornerRadius: CGFloat = 12
    static let carouselHeight: CGFloat = 132
    static let timelineImageGalleryAllowsHitTesting = true

    static func imageSectionHeight(for mode: ImageDisplayMode) -> CGFloat {
        switch mode {
        case .scroll:
            thumbnailSize.height
        case .carousel:
            carouselHeight
        }
    }
}

/// 气泡尾巴几何值。默认值只服务时间轴气泡；其他场景如需不同尾巴，应显式传入。
struct BubbleTailGeometry: Equatable {
    let size: CGSize
    let horizontalOffset: CGFloat

    static let timelineDefault = BubbleTailGeometry(
        size: CGSize(width: 8, height: 14),
        horizontalOffset: -6
    )

    var centerYOffset: CGFloat {
        -size.height / 2
    }
}

/// 气泡左侧的小三角「尾巴」，指向时间线心情节点，强化聊天气泡观感（见 05 §5.5）。
private struct BubbleTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

private struct PlaceholderImageGalleryView: View {
    let hexColors: [UInt32]
    let displayMode: ImageDisplayMode
    let allowsImageInteraction: Bool

    var body: some View {
        imageGallery
            .allowsHitTesting(allowsImageInteraction)
    }

    @ViewBuilder
    private var imageGallery: some View {
        switch displayMode {
        case .scroll:
            ScrollView(.horizontal) {
                LazyHStack(spacing: MomentCardLayout.thumbnailSpacing) {
                    ForEach(Array(hexColors.enumerated()), id: \.offset) { _, hex in
                        placeholder(hex)
                            .frame(
                                width: MomentCardLayout.thumbnailSize.width,
                                height: MomentCardLayout.thumbnailSize.height
                            )
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(height: MomentCardLayout.imageSectionHeight(for: .scroll))
            .frame(maxWidth: .infinity, alignment: .leading)
        case .carousel:
            TabView {
                ForEach(Array(hexColors.enumerated()), id: \.offset) { _, hex in
                    placeholder(hex)
                        .frame(maxWidth: .infinity)
                        .frame(height: MomentCardLayout.carouselHeight)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: hexColors.count > 1 ? .automatic : .never))
            .frame(height: MomentCardLayout.imageSectionHeight(for: .carousel))
        }
    }

    private func placeholder(_ hex: UInt32) -> some View {
        RoundedRectangle(cornerRadius: MomentCardLayout.thumbnailCornerRadius, style: .continuous)
            .fill(Color(hex: hex))
    }
}

/// 标签 chip（见 05 §5.6）：前缀「#」使用当前主色着色，其余文字为中性次级色。
struct TagChipView: View {
    let name: String

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        HStack(spacing: 2) {
            Text("#").foregroundStyle(theme.accent)
            Text(name).foregroundStyle(theme.bubbleBodyText)
        }
        .font(.footnote)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme.chipFill))
    }
}

#Preview {
    BubbleCardView(
        title: "欢迎来到时刻~",
        bodyText: "这里是你的个人时间轴，每一条记录都带着当时的心情。",
        tagNames: ["工作", "生活"],
        placeholderImageHexColors: [0xB678F5, 0x8E7B6B]
    )
    .environment(ThemeManager())
    .padding()
    .background(Color(hex: 0x121221))
}
