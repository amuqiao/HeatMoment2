import SwiftUI

/// 首页时间轴布局契约。
///
/// 它只描述日期、心情节点和 Moment 气泡的相对布局意图；轨道绘制在 `List` 行背景层中，
/// 和行前景阅读单元消费同一套行坐标，避免行级 swipe 动画影响轨道连续性。
/// 后续移动时间轴、调整日期列宽度、节点尺寸或气泡尖角关系时，应优先修改本类型，
/// 而不是在各个子视图里散写数值。
struct TimelineGeometry {
    static let standard = TimelineGeometry()

    let listHorizontalInset: CGFloat
    let dateColumnWidth: CGFloat
    let interColumnSpacing: CGFloat
    let nodeColumnWidth: CGFloat
    let nodeDiameter: CGFloat
    let nodeCenterY: CGFloat
    let rowGapHeight: CGFloat
    let titleToRailTopSpacing: CGFloat
    let firstNodeCenterYOffsetFromRailTop: CGFloat
    let railBottomOvershoot: CGFloat
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
        titleToRailTopSpacing: CGFloat = 12,
        firstNodeCenterYOffsetFromRailTop: CGFloat = 78,
        railBottomOvershoot: CGFloat = 260,
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
        self.titleToRailTopSpacing = titleToRailTopSpacing
        self.firstNodeCenterYOffsetFromRailTop = firstNodeCenterYOffsetFromRailTop
        self.railBottomOvershoot = railBottomOvershoot
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

    /// 轨道在 `List` 行背景坐标里的 x 坐标。
    ///
    /// `List` 行前景由 `rowInsets` 向内收束，行背景覆盖完整行宽。
    /// 因此轨道必须使用完整行坐标：内容层左缩进 + 阅读单元内节点中心。
    /// 这样静止态节点压在线上，左滑时系统只移动阅读单元，轨道仍是单根连续背景轴。
    var railCenterXInViewport: CGFloat {
        nodeCenterXInListRow
    }

    /// 心情节点相对完整列表行左边缘的理论绝对 x。用于测试“移动内容层”时的外部位移。
    var nodeCenterXInListRow: CGFloat {
        listHorizontalInset + nodeCenterXInReadingUnit
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
