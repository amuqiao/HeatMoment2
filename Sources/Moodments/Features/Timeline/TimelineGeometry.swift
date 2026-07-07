import SwiftUI

/// 首页时间轴坐标系统。
///
/// 时间轴不是 `TimelineRowView` 的装饰背景，而是首页时间轴场景里的稳定结构轴。
/// 日期、心情节点和 Moment 气泡只消费这里的命名锚点来定位自己。后续移动时间轴、
/// 调整日期列宽度、节点尺寸或气泡尖角关系时，应优先修改本类型，而不是在各个子视图里散写数值。
struct TimelineGeometry {
    static let standard = TimelineGeometry()

    let sceneCoordinateSpaceName = "TimelineListView.scroll"
    let listHorizontalInset: CGFloat = 20
    let dateColumnWidth: CGFloat = 64
    let interColumnSpacing: CGFloat = 12
    let nodeColumnWidth: CGFloat = 24
    let nodeDiameter: CGFloat = 13
    let nodeCenterY: CGFloat = 30
    let rowGapHeight: CGFloat = 20
    let initialRailTopY: CGFloat = 96
    let railLeadInHeight: CGFloat = 36
    let railBottomOvershoot: CGFloat = 260
    let bubbleTailSize = CGSize(width: 8, height: 14)
    let bubbleTailHorizontalOffset: CGFloat = -6

    var bubbleTailCenterY: CGFloat { nodeCenterY }
    var nodeTopPadding: CGFloat { nodeCenterY - nodeDiameter / 2 }
    var bubbleTailGeometry: BubbleTailGeometry {
        BubbleTailGeometry(size: bubbleTailSize, horizontalOffset: bubbleTailHorizontalOffset)
    }

    /// 轨道相对一行阅读单元左边缘的 x 坐标。
    var railCenterXInRow: CGFloat {
        dateColumnWidth + interColumnSpacing + nodeColumnWidth / 2
    }

    /// 轨道相对 `TimelineListView` viewport 左边缘的首帧初始 x 坐标。
    ///
    /// 运行时由 `TimelineSceneRailProbe` 测得真实列表内容起点；这个值只负责 layout
    /// probe 回传前的首帧位置。
    var initialRailCenterX: CGFloat {
        listHorizontalInset + railCenterXInRow
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

struct TimelineSceneRailAnchor: Equatable {
    let x: CGFloat
    let topY: CGFloat
}

struct TimelineSceneRailAnchorPreferenceKey: PreferenceKey {
    static let defaultValue: TimelineSceneRailAnchor? = nil

    static func reduce(
        value: inout TimelineSceneRailAnchor?,
        nextValue: () -> TimelineSceneRailAnchor?
    ) {
        guard let nextValue = nextValue() else { return }
        value = nextValue
    }
}
