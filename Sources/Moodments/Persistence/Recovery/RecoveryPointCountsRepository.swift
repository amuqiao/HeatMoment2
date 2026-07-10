import SwiftData

@ModelActor
actor RecoveryPointCountsRepository {
    func recoveryPointCounts() throws -> RecoveryPointCounts {
        let recordCount = try modelContext.fetchCount(FetchDescriptor<Moment>())
        let tagCount = try modelContext.fetchCount(FetchDescriptor<Tag>())
        let assetCount = try modelContext.fetchCount(FetchDescriptor<MomentImage>())
        return RecoveryPointCounts(
            recordCount: recordCount,
            tagCount: tagCount,
            assetCount: assetCount
        )
    }
}
