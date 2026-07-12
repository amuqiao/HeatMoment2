import Foundation

/// 预置引导 Moment（见 `product-mental-model.md` 空态引导、docs/product-mental-model.md）。
///
/// 首次使用或时间轴为空时，不做独立 Onboarding 页，而是用 3 条**不可删除/不可编辑**的本地静态
/// 数据承担引导职责：不落库为真实 `Moment`、不计入免费额度、不参与 iCloud 同步；用户产生
/// 第一条真实记录后不再展示（见 docs/product-mental-model.md §「单页信息架构」）。
struct GuidedMoment: Identifiable, Sendable {
    let id = UUID()
    /// i18n key（见 `Localizable.xcstrings`），非直接展示文案；展示时经 `title`/`bodyText`
    /// 计算属性按当前语言偏好解析（阶段7 D 本地化：空态引导是首屏最高可见内容，与 Paywall
    /// 同列为「译全」范围，见计划决策7）。
    private let titleKey: String
    private let bodyTextKey: String
    let mood: Mood
    let occurredAt: Date
    /// 模拟「图片」区的占位色块十六进制值（见 docs/current/implementation-truth.md §5.7：
    /// 「引导卡片内以主色/中性棕色块模拟'图片'占位」），空数组表示该条无图片区。
    let placeholderImageHexColors: [UInt32]

    /// 展示文案：经 `LanguagePreference.localizedString(_:)` 按当前语言偏好解析（见该类型
    /// 头部说明——`BubbleCardView`/`TimelineEntry` 均以 `String` 消费本属性，非 `Text`，故
    /// 不能用依赖 View 环境传播的 `LocalizedStringKey`）。
    var title: String { LanguagePreference.localizedString(String.LocalizationValue(titleKey)) }
    var bodyText: String { LanguagePreference.localizedString(String.LocalizationValue(bodyTextKey)) }

    private init(
        titleKey: String, bodyTextKey: String, mood: Mood, occurredAt: Date,
        placeholderImageHexColors: [UInt32]
    ) {
        self.titleKey = titleKey
        self.bodyTextKey = bodyTextKey
        self.mood = mood
        self.occurredAt = occurredAt
        self.placeholderImageHexColors = placeholderImageHexColors
    }

    /// 3 条固定引导内容，数组顺序即时间轴展示顺序（倒序时间轴，最新在上）。
    static let all: [GuidedMoment] = [
        GuidedMoment(
            titleKey: "guided.createNow.title",
            bodyTextKey: "guided.createNow.body",
            mood: .motivated,
            occurredAt: .now,
            placeholderImageHexColors: []
        ),
        GuidedMoment(
            titleKey: "guided.whatIsMoment.title",
            bodyTextKey: "guided.whatIsMoment.body",
            mood: .normal,
            occurredAt: .now.addingTimeInterval(-60),
            placeholderImageHexColors: []
        ),
        GuidedMoment(
            titleKey: "guided.welcome.title",
            bodyTextKey: "guided.welcome.body",
            mood: .happy,
            occurredAt: .now.addingTimeInterval(-120),
            placeholderImageHexColors: [0xB678F5, 0x8E7B6B]
        )
    ]
}
