import XCTest
import SwiftData
@testable import Moodments

/// `MomentEditorModel` 保存校验 / 默认情绪回退 / 脏检测测试（见 `docs/plans/implementation-plan.md`
/// 阶段 3、`docs/design/03-user-flows.md` §3.1）。
@MainActor
final class EditorSaveValidationTests: XCTestCase {
    private var container: ModelContainer!

    override func setUpWithError() throws {
        container = try ModelContainerConfig.makeInMemoryContainer()
    }

    override func tearDown() {
        container = nil
    }

    func testCanSaveRequiresAtLeastTitleBodyOrPhoto() {
        let model = MomentEditorModel(
            mode: .create, modelContainer: container, subscriptionService: SubscriptionService()
        )

        XCTAssertFalse(model.canSave, "标题/正文/照片均为空时不可保存")

        model.title = "有标题"
        XCTAssertTrue(model.canSave)

        model.title = ""
        model.bodyText = "有正文"
        XCTAssertTrue(model.canSave)

        model.bodyText = ""
        XCTAssertFalse(model.canSave)

        model.draftPhotos = [DraftPhoto(jpegData: Data([0x01]))]
        XCTAssertTrue(model.canSave, "至少有一张照片也可保存")
    }

    func testDefaultMoodFallsBackToLastThenNormal() {
        let withLastMood = MomentEditorModel(
            mode: .create, modelContainer: container, subscriptionService: SubscriptionService(),
            lastUsedMood: .happy
        )
        XCTAssertEqual(withLastMood.mood, .happy, "有历史选择应使用上次选择")

        let withoutLastMood = MomentEditorModel(
            mode: .create, modelContainer: container, subscriptionService: SubscriptionService()
        )
        XCTAssertEqual(withoutLastMood.mood, .normal, "无历史选择应回退到 .normal")
    }

    func testIsDirtyDetectsUnsavedChanges() {
        let model = MomentEditorModel(
            mode: .create, modelContainer: container, subscriptionService: SubscriptionService()
        )
        XCTAssertFalse(model.isDirty, "刚打开的新建态不应视为脏")

        model.title = "标题"
        XCTAssertTrue(model.isDirty, "改动标题后应视为脏")
    }

    func testAddPhotoRespectsQuotaAndRemovePhotoWorks() async {
        let model = MomentEditorModel(
            mode: .create, modelContainer: container, subscriptionService: SubscriptionService()
        )

        for _ in 0..<Quota.freePhotosPerMomentLimit {
            let check = await model.addPhoto(Data([0x01]))
            XCTAssertEqual(check, .allowed)
        }
        let exceededCheck = await model.addPhoto(Data([0x01]))
        XCTAssertEqual(exceededCheck, .exceeded(.photosPerMoment))
        XCTAssertEqual(model.draftPhotos.count, Quota.freePhotosPerMomentLimit)

        let firstID = model.draftPhotos[0].id
        model.removePhoto(id: firstID)
        XCTAssertEqual(model.draftPhotos.count, Quota.freePhotosPerMomentLimit - 1)
        XCTAssertFalse(model.draftPhotos.contains { $0.id == firstID })
    }

    /// `.edit` 态经 `load()` 载入既有数据后，未改动前不应视为脏；载入后修改字段应视为脏。
    func testEditModeLoadEstablishesCleanBaseline() async throws {
        let repository = MomentRepository(modelContainer: container)
        let id = try await repository.createMoment(
            title: "旧标题", bodyText: "旧正文", occurredAt: .now, mood: .sad
        )

        let model = MomentEditorModel(
            mode: .edit(id), modelContainer: container, subscriptionService: SubscriptionService()
        )
        XCTAssertFalse(model.isLoaded)

        try await model.load()

        XCTAssertTrue(model.isLoaded)
        XCTAssertEqual(model.title, "旧标题")
        XCTAssertEqual(model.mood, .sad)
        XCTAssertFalse(model.isDirty, "载入既有数据后、未改动前不应视为脏")

        model.title = "新标题"
        XCTAssertTrue(model.isDirty)
    }
}
