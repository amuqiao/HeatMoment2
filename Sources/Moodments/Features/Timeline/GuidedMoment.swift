import Foundation

/// 预置引导 Moment（见 `product-mental-model.md` 空态引导、02-information-architecture.md）。
///
/// 首次使用或时间轴为空时，不做独立 Onboarding 页，而是用 3 条**不可删除/不可编辑**的本地静态
/// 数据承担引导职责：不落库为真实 `Moment`、不计入免费额度、不参与 iCloud 同步；用户产生
/// 第一条真实记录后不再展示（见 02 §「单页信息架构」）。
struct GuidedMoment: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let bodyText: String
    let mood: Mood
    let occurredAt: Date
    /// 模拟「图片」区的占位色块十六进制值（见 05-design-system.md §5.7：
    /// 「引导卡片内以主色/中性棕色块模拟'图片'占位」），空数组表示该条无图片区。
    let placeholderImageHexColors: [UInt32]

    /// 3 条固定引导内容，数组顺序即时间轴展示顺序（倒序时间轴，最新在上）。
    static let all: [GuidedMoment] = [
        GuidedMoment(
            title: "马上创建",
            bodyText: "点击右下角的 + 按钮，记录你的第一个时刻吧。",
            mood: .motivated,
            occurredAt: .now,
            placeholderImageHexColors: []
        ),
        GuidedMoment(
            title: "什么是时刻?",
            bodyText: "时刻是一条带情绪身份的生活记忆，挂在可回看、可筛选、可整理的个人时间轴上。",
            mood: .normal,
            occurredAt: .now.addingTimeInterval(-60),
            placeholderImageHexColors: []
        ),
        GuidedMoment(
            title: "欢迎来到时刻~",
            bodyText: "这里是你的个人时间轴，每一条记录都带着当时的心情、标签与照片。",
            mood: .happy,
            occurredAt: .now.addingTimeInterval(-120),
            placeholderImageHexColors: [0xB678F5, 0x8E7B6B]
        )
    ]
}
