import SwiftUI

/// 首页时间轴的 resolved 坐标契约。
///
/// 它是 `TimelineLayoutResolver` 的输出，不是人工调参入口。后续移动时间轴、调整日期列宽度、
/// 节点尺寸或气泡尖角关系时，应优先修改 `TimelineLayoutTokens`，再由 resolver 派生本类型。
struct TimelineGeometry: Equatable {
    static let standard = TimelineLayoutResolver.resolve(
        scale: TimelineResponsiveScale(viewportWidth: 390)
    ).geometry

    let listHorizontalInset: CGFloat
    let dateColumnWidth: CGFloat
    let interColumnSpacing: CGFloat
    let nodeColumnWidth: CGFloat
    let nodeDiameter: CGFloat
    let nodeCenterY: CGFloat
    let railLeadInHeight: CGFloat
    let rowGapHeight: CGFloat
    let railWidth: CGFloat
    let bubbleTailSize: CGSize
    let bubbleTailHorizontalOffset: CGFloat

    init(
        listHorizontalInset: CGFloat,
        dateColumnWidth: CGFloat,
        interColumnSpacing: CGFloat,
        nodeColumnWidth: CGFloat,
        nodeDiameter: CGFloat,
        nodeCenterY: CGFloat,
        railLeadInHeight: CGFloat,
        rowGapHeight: CGFloat,
        railWidth: CGFloat,
        bubbleTailSize: CGSize,
        bubbleTailHorizontalOffset: CGFloat
    ) {
        precondition(railLeadInHeight >= 0, "railLeadInHeight must be non-negative")
        self.listHorizontalInset = listHorizontalInset
        self.dateColumnWidth = dateColumnWidth
        self.interColumnSpacing = interColumnSpacing
        self.nodeColumnWidth = nodeColumnWidth
        self.nodeDiameter = nodeDiameter
        self.nodeCenterY = nodeCenterY
        self.railLeadInHeight = railLeadInHeight
        self.rowGapHeight = rowGapHeight
        self.railWidth = railWidth
        self.bubbleTailSize = bubbleTailSize
        self.bubbleTailHorizontalOffset = bubbleTailHorizontalOffset
    }

    var bubbleTailCenterY: CGFloat { nodeCenterY }
    var nodeTopPadding: CGFloat { nodeCenterY - nodeDiameter / 2 }
    var firstNodeCenterYOffsetFromRailTop: CGFloat {
        railLeadInHeight + nodeCenterY
    }
    var bubbleTailGeometry: BubbleTailGeometry {
        BubbleTailGeometry(size: bubbleTailSize, horizontalOffset: bubbleTailHorizontalOffset)
    }

    /// 默认态第一条记录的心情节点中心 y。用于验证“旗杆顶点高于第一面旗”的呼吸空间。
    func firstNodeCenterY(railTopY: CGFloat) -> CGFloat {
        railTopY + firstNodeCenterYOffsetFromRailTop
    }

    /// 心情节点相对一行阅读单元左边缘的设计 x 坐标。
    ///
    /// 该值只用于阅读单元内部布局和测试约束；轨道绘制必须使用真实节点锚点。
    var nodeCenterXInReadingUnit: CGFloat {
        dateColumnWidth + interColumnSpacing + nodeColumnWidth / 2
    }

    /// 气泡卡片相对阅读单元左边缘的起点；对应行内 HStack 中日期列、节点列之后的位置。
    var bubbleLeadingXInReadingUnit: CGFloat {
        dateColumnWidth + interColumnSpacing + nodeColumnWidth + interColumnSpacing
    }

    /// 轨道在首页 viewport 坐标里的 x 坐标。
    ///
    /// `List` 行前景由 `rowInsets` 向内收束；场景轨道不属于 row，因此必须使用 viewport
    /// 坐标：内容层左缩进 + 阅读单元内节点中心。这样后续移动时间轴位置时，轨道、日期、
    /// 节点和气泡一起由同一坐标系统投影。
    var railCenterXInViewport: CGFloat {
        readingUnitOriginX + nodeCenterXInReadingUnit
    }

    /// 阅读单元相对首页 viewport 的起点。`List` row 通过 `rowInsets` 消费同一值。
    var readingUnitOriginX: CGFloat {
        listHorizontalInset
    }

    /// 心情节点相对首页 viewport 的理论绝对 x。用于测试坐标系统的一致性。
    var nodeCenterXInViewport: CGFloat {
        readingUnitOriginX + nodeCenterXInReadingUnit
    }

    var rowInsets: EdgeInsets {
        EdgeInsets(
            top: 0,
            leading: listHorizontalInset,
            bottom: 0,
            trailing: listHorizontalInset
        )
    }
}
