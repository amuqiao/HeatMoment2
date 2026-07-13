import XCTest
@testable import HeatMoment

final class CanonicalRepositoryParityTests: XCTestCase {
    func testCreateMomentWithImagesReturnsOrderedImageDataAndEditingPayload() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let tag = try await fixture.runtime.repository.createOrReuseTag(
            name: "工作",
            now: Date(timeIntervalSince1970: 10)
        )
        let imageDatas = [Data([0x01]), Data([0x02]), Data([0x03])]

        let momentID = try await fixture.runtime.repository.createMoment(
            title: "标题",
            bodyText: "正文",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .happy,
            tagIDs: [tag.id],
            imageDatas: imageDatas,
            now: Date(timeIntervalSince1970: 200)
        )

        let page = try await fixture.runtime.repository.fetchPage()
        let record = try XCTUnwrap(page.first)
        XCTAssertEqual(record.id, momentID)
        XCTAssertEqual(record.tagIDs, [tag.id])
        XCTAssertEqual(record.imageIDs.count, 3)
        let imageCount = try await fixture.runtime.repository.imageCount(momentID: momentID)
        XCTAssertEqual(imageCount, 3)

        let orderedImages = try await fixture.runtime.repository.orderedImageData(
            momentID: momentID)
        XCTAssertEqual(orderedImages.map(\.id), record.imageIDs)
        XCTAssertEqual(orderedImages.map(\.data), imageDatas)
        let secondImageData = try await fixture.runtime.repository.imageData(
            imageID: orderedImages[1].id)
        XCTAssertEqual(secondImageData, Data([0x02]))

        let payload = try await fixture.runtime.repository.editingPayload(id: momentID)
        XCTAssertEqual(payload.record.id, momentID)
        XCTAssertEqual(payload.tagNames[tag.id], "工作")
        XCTAssertEqual(payload.imageDatas, imageDatas)
    }

    func testUpdateMomentWithNilImagesKeepsImagesAndNonNilReplacesImages() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let momentID = try await fixture.runtime.repository.createMoment(
            title: "原标题",
            bodyText: "正文",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .normal,
            imageDatas: [Data([0xA1]), Data([0xA2])],
            now: Date(timeIntervalSince1970: 200)
        )
        let originalImages = try await fixture.runtime.repository.orderedImageData(
            momentID: momentID)

        try await fixture.runtime.repository.updateMoment(
            id: momentID,
            title: "只改标题",
            now: Date(timeIntervalSince1970: 300)
        )
        let keptImages = try await fixture.runtime.repository.orderedImageData(momentID: momentID)
        XCTAssertEqual(keptImages, originalImages)

        try await fixture.runtime.repository.updateMoment(
            id: momentID,
            imageDatas: [Data([0xB1]), Data([0xB2]), Data([0xB3])],
            now: Date(timeIntervalSince1970: 400)
        )

        let replacedPayload = try await fixture.runtime.repository.editingPayload(id: momentID)
        XCTAssertEqual(replacedPayload.imageDatas, [Data([0xB1]), Data([0xB2]), Data([0xB3])])
        let replacedImageCount = try await fixture.runtime.repository.imageCount(momentID: momentID)
        XCTAssertEqual(replacedImageCount, 3)
        do {
            _ = try await fixture.runtime.repository.imageData(imageID: originalImages[0].id)
            XCTFail("期望旧图片 ID 替换后不可读取")
        } catch RepositoryError.momentImageNotFound(let id) {
            XCTAssertEqual(id, originalImages[0].id)
        } catch {
            XCTFail("期望 RepositoryError.momentImageNotFound，实际抛出 \(error)")
        }
    }

    func testTerminalDeletedMomentCannotBeReadThroughDetailOrImageAPIs() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let momentID = try await repository.createMoment(
            title: "待彻底删除",
            bodyText: "正文",
            occurredAt: Date(timeIntervalSince1970: 100),
            mood: .sad,
            imageDatas: [Data([0xD1])],
            now: Date(timeIntervalSince1970: 200)
        )
        let images = try await repository.orderedImageData(momentID: momentID)
        let imageID = try XCTUnwrap(images.first?.id)

        try await repository.purgeMoment(id: momentID, now: Date(timeIntervalSince1970: 300))

        do {
            _ = try await repository.fetchMoment(id: momentID)
            XCTFail("期望 purgePending Moment 不可通过详情 API 读取")
        } catch RepositoryError.momentNotFound(let id) {
            XCTAssertEqual(id, momentID)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)")
        }
        do {
            _ = try await repository.editingPayload(id: momentID)
            XCTFail("期望 purgePending Moment 不可通过编辑 payload 读取")
        } catch RepositoryError.momentNotFound(let id) {
            XCTAssertEqual(id, momentID)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)")
        }
        do {
            _ = try await repository.orderedImageData(momentID: momentID)
            XCTFail("期望 purgePending Moment 不可通过图片列表读取")
        } catch RepositoryError.momentNotFound(let id) {
            XCTAssertEqual(id, momentID)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)")
        }
        do {
            _ = try await repository.imageCount(momentID: momentID)
            XCTFail("期望 purgePending Moment 不可读取图片数量")
        } catch RepositoryError.momentNotFound(let id) {
            XCTAssertEqual(id, momentID)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)")
        }
        do {
            _ = try await repository.imageData(imageID: imageID)
            XCTFail("期望 purgePending Moment 的图片 ID 不可直接读取")
        } catch RepositoryError.momentImageNotFound(let id) {
            XCTAssertEqual(id, imageID)
        } catch {
            XCTFail("期望 RepositoryError.momentImageNotFound，实际抛出 \(error)")
        }
    }

    func testCreateMomentWithImagesCleansNewBlobsWhenDatabaseWriteRollsBack() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let missingTagID = UUID()
        let initialListing = try fixture.runtime.assetStore.listStoredAssets()
        XCTAssertEqual(initialListing.contentHashes, [])

        do {
            _ = try await fixture.runtime.repository.createMoment(
                title: "失败写入",
                bodyText: "正文",
                occurredAt: Date(timeIntervalSince1970: 100),
                mood: .happy,
                tagIDs: [missingTagID],
                imageDatas: [Data([0xC1]), Data([0xC2])],
                now: Date(timeIntervalSince1970: 200)
            )
            XCTFail("期望缺失标签导致 DB 写入回滚")
        } catch RepositoryError.tagNotFound(let id) {
            XCTAssertEqual(id, missingTagID)
        } catch {
            XCTFail("期望 RepositoryError.tagNotFound，实际抛出 \(error)")
        }

        let finalListing = try fixture.runtime.assetStore.listStoredAssets()
        XCTAssertEqual(finalListing.contentHashes, [])
        let page = try await fixture.runtime.repository.fetchPage()
        XCTAssertEqual(page, [])
    }

    func testImageQueriesFailFastForMissingIDs() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let missingMomentID = UUID()
        let missingImageID = UUID()

        do {
            _ = try await fixture.runtime.repository.orderedImageData(momentID: missingMomentID)
            XCTFail("期望 missing moment 抛错")
        } catch RepositoryError.momentNotFound(let id) {
            XCTAssertEqual(id, missingMomentID)
        } catch {
            XCTFail("期望 RepositoryError.momentNotFound，实际抛出 \(error)")
        }

        do {
            _ = try await fixture.runtime.repository.imageData(imageID: missingImageID)
            XCTFail("期望 missing image 抛错")
        } catch RepositoryError.momentImageNotFound(let id) {
            XCTAssertEqual(id, missingImageID)
        } catch {
            XCTFail("期望 RepositoryError.momentImageNotFound，实际抛出 \(error)")
        }
    }

    func testFilteredTimelineAndAggregationsShareCanonicalSemantics() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let repository = fixture.runtime.repository
        let work = try await repository.createOrReuseTag(
            name: "工作",
            now: Date(timeIntervalSince1970: 10)
        )
        let life = try await repository.createOrReuseTag(
            name: "生活",
            now: Date(timeIntervalSince1970: 20)
        )
        let year = 2026
        let base = Self.date(year: year, month: 3, day: 1, hour: 10)
        let bothID = try await repository.createMoment(
            title: "both",
            bodyText: "",
            occurredAt: base,
            mood: .happy,
            tagIDs: [work.id, life.id],
            now: Date(timeIntervalSince1970: 30)
        )
        let workOnlyID = try await repository.createMoment(
            title: "workOnly",
            bodyText: "",
            occurredAt: base.addingTimeInterval(3_600),
            mood: .sad,
            tagIDs: [work.id],
            now: Date(timeIntervalSince1970: 40)
        )
        _ = try await repository.createMoment(
            title: "otherDay",
            bodyText: "",
            occurredAt: Self.date(year: year, month: 3, day: 2, hour: 10),
            mood: .normal,
            now: Date(timeIntervalSince1970: 50)
        )
        let deletedID = try await repository.createMoment(
            title: "deleted",
            bodyText: "",
            occurredAt: Self.date(year: year, month: 3, day: 3, hour: 10),
            mood: .angry,
            now: Date(timeIntervalSince1970: 60)
        )
        try await repository.softDeleteMoment(
            id: deletedID,
            now: Date(timeIntervalSince1970: 70)
        )

        let filter = FilterCondition(tagIDs: [work.id, life.id])
        let filteredPage = try await repository.fetchPage(filter: filter)
        XCTAssertEqual(filteredPage.map(\.id), [bothID])

        let unfilteredDayMoods = try await repository.moodByDay(year: year, filter: nil)
        let filteredDayMoods = try await repository.moodByDay(year: year, filter: filter)
        let firstDay = try XCTUnwrap(Calendar.current.ordinality(of: .day, in: .year, for: base))
        XCTAssertEqual(unfilteredDayMoods[firstDay], .sad, "同一天最后一条 active 记录获胜")
        XCTAssertEqual(filteredDayMoods[firstDay], .happy, "标签 AND 筛选只保留 both 记录")

        let counts = try await repository.moodCounts(year: year)
        XCTAssertEqual(counts[.happy], 1)
        XCTAssertEqual(counts[.sad], 1)
        XCTAssertEqual(counts[.normal], 1)
        XCTAssertNil(counts[.angry], "软删除记录不参与统计")

        let years = try await repository.availableYears(includingCurrentYear: 2030)
        XCTAssertEqual(years, [year, 2030])
        let workOnlyRecord = try await repository.fetchMoment(id: workOnlyID)
        XCTAssertEqual(workOnlyRecord.title, "workOnly")
    }

    func testFindTagReturnsHitAndMiss() async throws {
        let fixture = try makeFixture()
        defer { fixture.cleanup() }
        let created = try await fixture.runtime.repository.createOrReuseTag(name: "旅行")

        let found = try await fixture.runtime.repository.findTag(named: "旅行")
        let missing = try await fixture.runtime.repository.findTag(named: "不存在")

        XCTAssertEqual(found?.id, created.id)
        XCTAssertNil(missing)
    }

    private func makeFixture() throws -> CanonicalRepositoryParityFixture {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "CanonicalRepositoryParityTests-\(UUID().uuidString)", isDirectory: true)
        let runtime = try CanonicalLibraryRuntime.makeInMemoryForTests(
            assetDirectoryURL: directory.appendingPathComponent("Assets", isDirectory: true)
        )
        return CanonicalRepositoryParityFixture(rootDirectory: directory, runtime: runtime)
    }

    private static func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        return Calendar.current.date(from: components)!
    }
}

private struct CanonicalRepositoryParityFixture {
    let rootDirectory: URL
    let runtime: CanonicalLibraryRuntime

    func cleanup() {
        try? FileManager.default.removeItem(at: rootDirectory)
    }
}
