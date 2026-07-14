import Foundation

enum DefaultLibrarySeeder {
    static let currentSeedVersion = CanonicalStore.currentDefaultSeedVersion
    static var defaultTagNames: [String] {
        [
            LanguagePreference.localizedString("工作"),
            LanguagePreference.localizedString("生活"),
            LanguagePreference.localizedString("健康")
        ]
    }

    static func seedIfNeeded(using repository: CanonicalLibraryRepository) async throws -> Bool {
        try await repository.seedDefaultLibraryIfNeeded(
            tagNames: defaultTagNames,
            moments: defaultMoments(),
            seedVersion: currentSeedVersion,
            now: .now
        )
    }

    private static func defaultMoments(now: Date = .now) -> [CanonicalDefaultLibrarySeedMoment] {
        [
            CanonicalDefaultLibrarySeedMoment(
                title: LanguagePreference.localizedString("马上创建"),
                bodyText: LanguagePreference.localizedString("点击右下角的 + 按钮，记录你的第一个时刻吧。"),
                occurredAt: now,
                mood: .motivated,
                tagName: LanguagePreference.localizedString("工作")
            ),
            CanonicalDefaultLibrarySeedMoment(
                title: LanguagePreference.localizedString("什么是时刻?"),
                bodyText: LanguagePreference.localizedString("时刻是一条带情绪身份的生活记忆，挂在可回看、可筛选、可整理的个人时间轴上。"),
                occurredAt: now.addingTimeInterval(-60),
                mood: .normal,
                tagName: LanguagePreference.localizedString("生活")
            ),
            CanonicalDefaultLibrarySeedMoment(
                title: LanguagePreference.localizedString("欢迎来到心绪日记~"),
                bodyText: LanguagePreference.localizedString("这里是你的个人时间轴，每一条记录都带着当时的心情、标签与照片。"),
                occurredAt: now.addingTimeInterval(-120),
                mood: .happy,
                tagName: LanguagePreference.localizedString("健康")
            )
        ]
    }
}
