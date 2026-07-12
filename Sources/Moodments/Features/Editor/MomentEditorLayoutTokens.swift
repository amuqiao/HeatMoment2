import SwiftUI

/// Moment 编辑页的设计意图 token。
///
/// 本类型是后续调编辑页呼吸间隔和接皮肤时的入口：只放“希望看到什么”的语义值，
/// 不放 `EdgeInsets`、`frame` 这类 SwiftUI 派生结果。顶部操作栏、心情/标签行和正文区
/// 同属一个垂直布局系统，避免继续被系统 toolbar 与 ScrollView padding 分别控制。
struct MomentEditorLayoutTokens: Equatable {
    static let standard = MomentEditorLayoutTokens()

    let pageHorizontalInset: CGFloat
    let pageBottomInset: CGFloat
    let topChromeHorizontalPadding: CGFloat
    let topChromeVerticalPadding: CGFloat
    let topChromeMinHeight: CGFloat
    let topChromeActionSlotWidth: CGFloat
    let topChromeItemSpacing: CGFloat
    let topChromeToSelectorGap: CGFloat
    let selectorRowGap: CGFloat
    let selectorMinHeight: CGFloat
    let selectorIconWidth: CGFloat
    let selectorChevronWidth: CGFloat
    let selectorCornerRadius: CGFloat
    let selectorContentSpacing: CGFloat
    let selectorHorizontalPadding: CGFloat
    let selectorToTextPanelGap: CGFloat
    let textPanelToPhotoSectionGap: CGFloat
    let textPanelFieldSpacing: CGFloat
    let bodyMinHeight: CGFloat
    let dateTimeChipHorizontalPadding: CGFloat
    let dateTimeChipVerticalPadding: CGFloat
    let tagChipCornerRadius: CGFloat
    let tagChipHorizontalPadding: CGFloat
    let tagChipVerticalPadding: CGFloat
    let tagChipSpacing: CGFloat

    init(
        pageHorizontalInset: CGFloat = 16,  // 编辑页内容左右边距
        pageBottomInset: CGFloat = 56,  // 滚动内容底部避让距离
        topChromeHorizontalPadding: CGFloat = 16,  // 顶部取消/日期时间/保存栏左右边距
        topChromeVerticalPadding: CGFloat = 10,  // 顶部操作栏上下内边距
        topChromeMinHeight: CGFloat = 56,  // 顶部操作栏最小高度
        topChromeActionSlotWidth: CGFloat = 64,  // 取消/保存按钮槽宽，保证中间日期时间居中
        topChromeItemSpacing: CGFloat = 8,  // 顶部操作栏内部元素间距
        topChromeToSelectorGap: CGFloat = 0,  // 顶部操作栏底部到心情/标签行顶部的呼吸间隔
        selectorRowGap: CGFloat = 12,  // 心情容器和标签容器之间的横向间距
        selectorMinHeight: CGFloat = 40,  // 心情/标签容器最小高度
        selectorIconWidth: CGFloat = 28,  // 心情/标签容器左侧图标槽宽
        selectorChevronWidth: CGFloat = 22,  // 心情/标签容器右侧箭头槽宽
        selectorCornerRadius: CGFloat = 14,  // 心情/标签容器圆角
        selectorContentSpacing: CGFloat = 8,  // 心情/标签容器内部元素间距
        selectorHorizontalPadding: CGFloat = 16,  // 心情/标签容器内部左右留白
        selectorToTextPanelGap: CGFloat = 18,  // 心情/标签行到底部编辑框的呼吸间隔
        textPanelToPhotoSectionGap: CGFloat = 20,  // 编辑框到图片区域的呼吸间隔
        textPanelFieldSpacing: CGFloat = 14,  // 标题、分割线、正文之间的间距
        bodyMinHeight: CGFloat = 132,  // 正文输入区最小高度
        dateTimeChipHorizontalPadding: CGFloat = 14,  // 日期/时间胶囊左右留白
        dateTimeChipVerticalPadding: CGFloat = 8,  // 日期/时间胶囊上下留白
        tagChipCornerRadius: CGFloat = 7,  // 已选标签小胶囊圆角
        tagChipHorizontalPadding: CGFloat = 8,  // 已选标签小胶囊左右留白
        tagChipVerticalPadding: CGFloat = 3,  // 已选标签小胶囊上下留白
        tagChipSpacing: CGFloat = 6  // 多个已选标签之间的间距
    ) {
        self.pageHorizontalInset = pageHorizontalInset
        self.pageBottomInset = pageBottomInset
        self.topChromeHorizontalPadding = topChromeHorizontalPadding
        self.topChromeVerticalPadding = topChromeVerticalPadding
        self.topChromeMinHeight = topChromeMinHeight
        self.topChromeActionSlotWidth = topChromeActionSlotWidth
        self.topChromeItemSpacing = topChromeItemSpacing
        self.topChromeToSelectorGap = topChromeToSelectorGap
        self.selectorRowGap = selectorRowGap
        self.selectorMinHeight = selectorMinHeight
        self.selectorIconWidth = selectorIconWidth
        self.selectorChevronWidth = selectorChevronWidth
        self.selectorCornerRadius = selectorCornerRadius
        self.selectorContentSpacing = selectorContentSpacing
        self.selectorHorizontalPadding = selectorHorizontalPadding
        self.selectorToTextPanelGap = selectorToTextPanelGap
        self.textPanelToPhotoSectionGap = textPanelToPhotoSectionGap
        self.textPanelFieldSpacing = textPanelFieldSpacing
        self.bodyMinHeight = bodyMinHeight
        self.dateTimeChipHorizontalPadding = dateTimeChipHorizontalPadding
        self.dateTimeChipVerticalPadding = dateTimeChipVerticalPadding
        self.tagChipCornerRadius = tagChipCornerRadius
        self.tagChipHorizontalPadding = tagChipHorizontalPadding
        self.tagChipVerticalPadding = tagChipVerticalPadding
        self.tagChipSpacing = tagChipSpacing

        validate()
    }

    private func validate() {
        precondition(pageHorizontalInset >= 0, "pageHorizontalInset must be non-negative")
        precondition(pageBottomInset >= 0, "pageBottomInset must be non-negative")
        precondition(topChromeMinHeight >= 0, "topChromeMinHeight must be non-negative")
        precondition(topChromeToSelectorGap >= 0, "topChromeToSelectorGap must be non-negative")
        precondition(selectorMinHeight >= 0, "selectorMinHeight must be non-negative")
        precondition(selectorToTextPanelGap >= 0, "selectorToTextPanelGap must be non-negative")
        precondition(
            textPanelToPhotoSectionGap >= 0,
            "textPanelToPhotoSectionGap must be non-negative"
        )
        precondition(bodyMinHeight >= 0, "bodyMinHeight must be non-negative")
    }
}

/// Moment 编辑页可直接被 SwiftUI View 消费的派生布局。
struct MomentEditorLayoutMetrics: Equatable {
    static let standard = MomentEditorLayoutResolver.resolve(
        tokens: .standard,
        scale: TimelineResponsiveScale(viewportWidth: 390)
    )

    let pageHorizontalInset: CGFloat
    let pageBottomInset: CGFloat
    let topChromeHorizontalPadding: CGFloat
    let topChromeVerticalPadding: CGFloat
    let topChromeMinHeight: CGFloat
    let topChromeActionSlotWidth: CGFloat
    let topChromeItemSpacing: CGFloat
    let topChromeToSelectorGap: CGFloat
    let selectorRowGap: CGFloat
    let selectorMinHeight: CGFloat
    let selectorIconWidth: CGFloat
    let selectorChevronWidth: CGFloat
    let selectorCornerRadius: CGFloat
    let selectorContentSpacing: CGFloat
    let selectorHorizontalPadding: CGFloat
    let selectorToTextPanelGap: CGFloat
    let textPanelToPhotoSectionGap: CGFloat
    let textPanelFieldSpacing: CGFloat
    let bodyMinHeight: CGFloat
    let dateTimeChipHorizontalPadding: CGFloat
    let dateTimeChipVerticalPadding: CGFloat
    let tagChipCornerRadius: CGFloat
    let tagChipHorizontalPadding: CGFloat
    let tagChipVerticalPadding: CGFloat
    let tagChipSpacing: CGFloat

    var contentInsets: EdgeInsets {
        EdgeInsets(
            top: topChromeToSelectorGap,
            leading: pageHorizontalInset,
            bottom: pageBottomInset,
            trailing: pageHorizontalInset
        )
    }
}

/// 将编辑页设计 token 解析为稳定坐标。
enum MomentEditorLayoutResolver {
    static func resolve(
        tokens: MomentEditorLayoutTokens = .standard,
        scale: TimelineResponsiveScale
    ) -> MomentEditorLayoutMetrics {
        MomentEditorLayoutMetrics(
            pageHorizontalInset: scale.horizontal(tokens.pageHorizontalInset),
            pageBottomInset: scale.vertical(tokens.pageBottomInset),
            topChromeHorizontalPadding: scale.horizontal(tokens.topChromeHorizontalPadding),
            topChromeVerticalPadding: scale.vertical(tokens.topChromeVerticalPadding),
            topChromeMinHeight: scale.vertical(tokens.topChromeMinHeight),
            topChromeActionSlotWidth: scale.horizontal(tokens.topChromeActionSlotWidth),
            topChromeItemSpacing: scale.horizontal(tokens.topChromeItemSpacing),
            topChromeToSelectorGap: scale.vertical(tokens.topChromeToSelectorGap),
            selectorRowGap: scale.horizontal(tokens.selectorRowGap),
            selectorMinHeight: scale.vertical(tokens.selectorMinHeight),
            selectorIconWidth: scale.horizontal(tokens.selectorIconWidth),
            selectorChevronWidth: scale.horizontal(tokens.selectorChevronWidth),
            selectorCornerRadius: scale.component(tokens.selectorCornerRadius),
            selectorContentSpacing: scale.horizontal(tokens.selectorContentSpacing),
            selectorHorizontalPadding: scale.horizontal(tokens.selectorHorizontalPadding),
            selectorToTextPanelGap: scale.vertical(tokens.selectorToTextPanelGap),
            textPanelToPhotoSectionGap: scale.vertical(tokens.textPanelToPhotoSectionGap),
            textPanelFieldSpacing: scale.vertical(tokens.textPanelFieldSpacing),
            bodyMinHeight: scale.vertical(tokens.bodyMinHeight),
            dateTimeChipHorizontalPadding: scale.horizontal(tokens.dateTimeChipHorizontalPadding),
            dateTimeChipVerticalPadding: scale.vertical(tokens.dateTimeChipVerticalPadding),
            tagChipCornerRadius: scale.component(tokens.tagChipCornerRadius),
            tagChipHorizontalPadding: scale.horizontal(tokens.tagChipHorizontalPadding),
            tagChipVerticalPadding: scale.vertical(tokens.tagChipVerticalPadding),
            tagChipSpacing: scale.horizontal(tokens.tagChipSpacing)
        )
    }
}
