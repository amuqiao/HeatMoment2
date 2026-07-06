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

    @Environment(ThemeManager.self) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(AppTypography.cardTitle)
                .foregroundStyle(theme.bubbleTitleText)
                .lineLimit(1)

            if !bodyText.isEmpty {
                Text(bodyText)
                    .font(AppTypography.body)
                    .foregroundStyle(theme.bubbleBodyText)
                    .lineLimit(3)
                    .truncationMode(.tail)
            }

            if !placeholderImageHexColors.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(placeholderImageHexColors.enumerated()), id: \.offset) { _, hex in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(hex: hex))
                            .frame(width: 72, height: 72)
                    }
                }
            } else if !imageIDs.isEmpty {
                // 时间轴气泡整行已有独立点击语义（打开预览阅读卡片），故不传 `onTapImage`，
                // 避免与行级 `onTapGesture` 冲突（见 `ThumbnailStripView` 头部说明）。
                ThumbnailStripView(imageIDs: imageIDs)
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
                .overlay(alignment: .leading) {
                    BubbleTailShape()
                        .fill(theme.bubbleBackground)
                        .frame(width: 8, height: 14)
                        .offset(x: -6)
                }
        )
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
