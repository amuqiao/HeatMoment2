import SwiftUI

/// 字体层级（系统字体，见 docs/current/implementation-truth.md §5.8）：全局使用 iOS 系统字体（San Francisco /
/// 中文自动回退 PingFang SC），不内嵌自定义字体；数字类文字（日期/价格/次数）统一使用
/// Bold/Semibold 权重制造视觉锚点。全部基于系统 Text Style，支持 Dynamic Type 缩放。
enum AppTypography {
    /// 页面大标题（时刻 / 月订阅 / HeatMoment）。
    static let pageTitle = Font.largeTitle.bold()

    /// 时间轴日期大数字（如「17」）。
    static let timelineDayNumber = Font.title2.bold()

    /// 时间轴月份小字（如「5月」）。
    static let timelineMonth = Font.footnote

    /// 时间轴时分（如「17:06」）。
    static let timelineTime = Font.footnote

    /// 卡片/分组标题。
    static let cardTitle = Font.headline.weight(.semibold)

    /// 正文/摘要。
    static let body = Font.body

    /// 次级说明文字（副标题、占位符、页脚）。
    static let caption = Font.footnote

    /// 按钮文字。
    static let button = Font.headline.weight(.semibold)
}
