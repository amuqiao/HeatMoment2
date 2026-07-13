import CoreGraphics

/// 首页 Timeline 的设计意图 token。
///
/// 本类型是后续调布局和接皮肤时的入口：只放“希望看到什么”的语义值，不放
/// `restingFirstNodeCenterY`、`bubbleTailHorizontalOffset` 这类需要由布局系统推导的结果。
struct TimelineLayoutTokens: Equatable {
    static let standard = TimelineLayoutTokens()

    let listHorizontalInset: CGFloat
    let dateColumnWidth: CGFloat
    let columnSpacing: CGFloat
    let nodeColumnWidth: CGFloat
    let nodeDiameter: CGFloat
    let nodeCenterYInMoment: CGFloat
    let railTopToFirstMomentTopGap: CGFloat
    let momentGap: CGFloat
    let nodeToBubbleTailGap: CGFloat
    let railWidth: CGFloat
    let bubbleTailSize: CGSize
    let expandedTitleSlotBottomY: CGFloat
    let expandedTitleTopPadding: CGFloat
    let titleToRailTopGap: CGFloat
    let railBottomOvershoot: CGFloat
    let topChromeHorizontalPadding: CGFloat
    let topChromeVerticalPadding: CGFloat
    let fabDiameter: CGFloat
    let fabBottomPadding: CGFloat
    let fabSafetyGap: CGFloat
    let fabVisualProtectionInset: CGFloat

    init(
        listHorizontalInset: CGFloat = 16,  // 首页内容左右边距；越大整体越向中间收
        dateColumnWidth: CGFloat = 50,  // 日期列宽度；越大日期区更宽，时间轴和气泡右移
        columnSpacing: CGFloat = 6,  // 日期、节点、气泡之间的横向间距
        nodeColumnWidth: CGFloat = 24,  // 心情节点列宽；越大节点列更宽，气泡起点更靠右
        nodeDiameter: CGFloat = 20,  // 心情节点外圈直径；越大时间轴上的圆点越大
        nodeCenterYInMoment: CGFloat = 24,  // 节点在每条 moment 容器内的垂直中心
        railTopToFirstMomentTopGap: CGFloat = 2,  // 时间轴顶点到第一条 moment 容器顶部的距离
        momentGap: CGFloat = 20,  // moment 与 moment 之间的垂直呼吸间隔
        nodeToBubbleTailGap: CGFloat = 5,  // 心情节点右缘到气泡尖角的水平间隔
        railWidth: CGFloat = 2,  // 时间轴竖线宽度
        bubbleTailSize: CGSize = CGSize(width: 8, height: 14),  // 气泡尖角尺寸
        expandedTitleSlotBottomY: CGFloat = 44,  // 展开态标题槽底部位置
        expandedTitleTopPadding: CGFloat = 0,  // 展开态标题顶部补偿
        titleToRailTopGap: CGFloat = 6,  // “时刻”标题底部到时间轴顶点的呼吸间隔
        railBottomOvershoot: CGFloat = 48,  // 时间轴轨道底部视觉延伸；滚动尾部净空会同时保护 FAB
        topChromeHorizontalPadding: CGFloat = 18,  // 顶部日历/设置区左右边距
        topChromeVerticalPadding: CGFloat = 8,  // 顶部日历/设置区上下边距
        fabDiameter: CGFloat = 64,  // 底部新建按钮直径
        fabBottomPadding: CGFloat = 18,  // 新建按钮到底部安全区的距离
        fabSafetyGap: CGFloat = 4,  // 内容与新建按钮之间的安全间隔
        fabVisualProtectionInset: CGFloat = 8  // 新建按钮视觉保护余量（含阴影）
    ) {
        Self.validate(
            railTopToFirstMomentTopGap: railTopToFirstMomentTopGap,
            titleToRailTopGap: titleToRailTopGap,
            momentGap: momentGap,
            nodeToBubbleTailGap: nodeToBubbleTailGap,
            fabVisualProtectionInset: fabVisualProtectionInset
        )

        self.listHorizontalInset = listHorizontalInset
        self.dateColumnWidth = dateColumnWidth
        self.columnSpacing = columnSpacing
        self.nodeColumnWidth = nodeColumnWidth
        self.nodeDiameter = nodeDiameter
        self.nodeCenterYInMoment = nodeCenterYInMoment
        self.railTopToFirstMomentTopGap = railTopToFirstMomentTopGap
        self.momentGap = momentGap
        self.nodeToBubbleTailGap = nodeToBubbleTailGap
        self.railWidth = railWidth
        self.bubbleTailSize = bubbleTailSize
        self.expandedTitleSlotBottomY = expandedTitleSlotBottomY
        self.expandedTitleTopPadding = expandedTitleTopPadding
        self.titleToRailTopGap = titleToRailTopGap
        self.railBottomOvershoot = railBottomOvershoot
        self.topChromeHorizontalPadding = topChromeHorizontalPadding
        self.topChromeVerticalPadding = topChromeVerticalPadding
        self.fabDiameter = fabDiameter
        self.fabBottomPadding = fabBottomPadding
        self.fabSafetyGap = fabSafetyGap
        self.fabVisualProtectionInset = fabVisualProtectionInset
    }

    private static func validate(
        railTopToFirstMomentTopGap: CGFloat,
        titleToRailTopGap: CGFloat,
        momentGap: CGFloat,
        nodeToBubbleTailGap: CGFloat,
        fabVisualProtectionInset: CGFloat
    ) {
        precondition(
            railTopToFirstMomentTopGap >= 0,
            "railTopToFirstMomentTopGap must be non-negative"
        )
        precondition(titleToRailTopGap >= 0, "titleToRailTopGap must be non-negative")
        precondition(momentGap >= 0, "momentGap must be non-negative")
        precondition(nodeToBubbleTailGap >= 0, "nodeToBubbleTailGap must be non-negative")
        precondition(fabVisualProtectionInset >= 0, "fabVisualProtectionInset must be non-negative")
    }
}

/// 将设计 token 解析为 SwiftUI View 可直接消费的稳定坐标。
enum TimelineLayoutResolver {
    static func resolve(
        tokens: TimelineLayoutTokens = .standard,
        scale: TimelineResponsiveScale
    ) -> TimelineSceneLayout {
        let geometry = resolveGeometry(tokens: tokens, scale: scale)
        return TimelineSceneLayout(
            home: resolveHome(tokens: tokens, scale: scale),
            viewport: resolveViewport(tokens: tokens, scale: scale),
            geometry: geometry
        )
    }

    private static func resolveGeometry(
        tokens: TimelineLayoutTokens,
        scale: TimelineResponsiveScale
    ) -> TimelineGeometry {
        let listHorizontalInset = scale.horizontal(tokens.listHorizontalInset)
        let dateColumnWidth = scale.horizontal(tokens.dateColumnWidth)
        let columnSpacing = scale.horizontal(tokens.columnSpacing)
        let nodeDiameter = scale.component(tokens.nodeDiameter)
        let nodeColumnWidth = max(
            scale.horizontal(tokens.nodeColumnWidth),
            nodeDiameter + scale.horizontal(2)
        )
        let nodeCenterY = scale.vertical(tokens.nodeCenterYInMoment)
        let nodeToBubbleTailGap = scale.horizontal(tokens.nodeToBubbleTailGap)
        let bubbleTailHorizontalOffset = resolveBubbleTailHorizontalOffset(
            dateColumnWidth: dateColumnWidth,
            columnSpacing: columnSpacing,
            nodeColumnWidth: nodeColumnWidth,
            nodeDiameter: nodeDiameter,
            nodeToBubbleTailGap: nodeToBubbleTailGap
        )

        return TimelineGeometry(
            listHorizontalInset: listHorizontalInset,
            dateColumnWidth: dateColumnWidth,
            interColumnSpacing: columnSpacing,
            nodeColumnWidth: nodeColumnWidth,
            nodeDiameter: nodeDiameter,
            nodeCenterY: nodeCenterY,
            rowGapHeight: scale.vertical(tokens.momentGap),
            railWidth: scale.component(tokens.railWidth),
            bubbleTailSize: CGSize(
                width: scale.horizontal(tokens.bubbleTailSize.width),
                height: scale.vertical(tokens.bubbleTailSize.height)
            ),
            bubbleTailHorizontalOffset: bubbleTailHorizontalOffset
        )
    }

    private static func resolveHome(
        tokens: TimelineLayoutTokens,
        scale: TimelineResponsiveScale
    ) -> TimelineHomeLayout {
        TimelineHomeLayout(
            topChromeHorizontalPadding: scale.horizontal(tokens.topChromeHorizontalPadding),
            topChromeVerticalPadding: scale.vertical(tokens.topChromeVerticalPadding),
            fabDiameter: scale.component(tokens.fabDiameter),
            fabBottomPadding: scale.vertical(tokens.fabBottomPadding),
            fabSafetyGap: scale.vertical(tokens.fabSafetyGap),
            fabVisualProtectionInset: scale.component(tokens.fabVisualProtectionInset)
        )
    }

    private static func resolveViewport(
        tokens: TimelineLayoutTokens,
        scale: TimelineResponsiveScale
    ) -> TimelineViewportLayout {
        TimelineViewportLayout(
            expandedTitleSlotBottomY: scale.vertical(tokens.expandedTitleSlotBottomY),
            expandedTitleTopPadding: scale.vertical(tokens.expandedTitleTopPadding),
            titleToRailTopGap: scale.vertical(tokens.titleToRailTopGap),
            railTopToFirstMomentTopGap: scale.vertical(tokens.railTopToFirstMomentTopGap),
            railBottomOvershoot: scale.vertical(tokens.railBottomOvershoot)
        )
    }

    private static func resolveBubbleTailHorizontalOffset(
        dateColumnWidth: CGFloat,
        columnSpacing: CGFloat,
        nodeColumnWidth: CGFloat,
        nodeDiameter: CGFloat,
        nodeToBubbleTailGap: CGFloat
    ) -> CGFloat {
        let nodeCenterX = dateColumnWidth + columnSpacing + nodeColumnWidth / 2
        let nodeRightEdgeX = nodeCenterX + nodeDiameter / 2
        let bubbleLeadingX = dateColumnWidth + columnSpacing + nodeColumnWidth + columnSpacing
        let tailTipX = nodeRightEdgeX + nodeToBubbleTailGap
        return tailTipX - bubbleLeadingX
    }
}
