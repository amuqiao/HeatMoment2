import SwiftUI

/// 首页时间轴布局契约。
///
/// 它是首页时间轴的坐标系统，而不是某条竖线的样式对象：场景轨道、日期列、心情节点
/// 和 Moment 气泡都从这里读取锚点。后续移动时间轴、调整日期列宽度、节点尺寸或气泡
/// 尖角关系时，应优先修改本类型，而不是在各个子视图里散写数值。
struct TimelineGeometry {
    static let standard = TimelineGeometry()

    let listHorizontalInset: CGFloat
    let dateColumnWidth: CGFloat
    let interColumnSpacing: CGFloat
    let nodeColumnWidth: CGFloat
    let nodeDiameter: CGFloat
    let nodeCenterY: CGFloat
    let rowGapHeight: CGFloat
    let firstNodeCenterYOffsetFromRailTop: CGFloat
    let railWidth: CGFloat
    let bubbleTailSize: CGSize
    let bubbleTailHorizontalOffset: CGFloat

    init(
        listHorizontalInset: CGFloat = 20,
        dateColumnWidth: CGFloat = 64,
        interColumnSpacing: CGFloat = 12,
        nodeColumnWidth: CGFloat = 24,
        nodeDiameter: CGFloat = 13,
        nodeCenterY: CGFloat = 30,
        rowGapHeight: CGFloat = 20,
        firstNodeCenterYOffsetFromRailTop: CGFloat = 60,
        railWidth: CGFloat = 1,
        bubbleTailSize: CGSize = CGSize(width: 8, height: 14),
        bubbleTailHorizontalOffset: CGFloat = -6
    ) {
        self.listHorizontalInset = listHorizontalInset
        self.dateColumnWidth = dateColumnWidth
        self.interColumnSpacing = interColumnSpacing
        self.nodeColumnWidth = nodeColumnWidth
        self.nodeDiameter = nodeDiameter
        self.nodeCenterY = nodeCenterY
        self.rowGapHeight = rowGapHeight
        self.firstNodeCenterYOffsetFromRailTop = firstNodeCenterYOffsetFromRailTop
        self.railWidth = railWidth
        self.bubbleTailSize = bubbleTailSize
        self.bubbleTailHorizontalOffset = bubbleTailHorizontalOffset
    }

    var bubbleTailCenterY: CGFloat { nodeCenterY }
    var nodeTopPadding: CGFloat { nodeCenterY - nodeDiameter / 2 }
    var railLeadInHeight: CGFloat {
        firstNodeCenterYOffsetFromRailTop - nodeCenterY
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
