#if DEBUG
    import XCTest
    @testable import HeatMoment

    final class SubscriptionDebugOverrideTests: XCTestCase {
        func testDebugOverrideIsActiveForNormalDebugRun() {
            XCTAssertTrue(
                SubscriptionDebugOverride.isActive(arguments: ["HeatMoment"], environment: [:])
            )
        }

        func testDebugOverrideCanBeDisabledByLaunchArgument() {
            XCTAssertFalse(
                SubscriptionDebugOverride.isActive(
                    arguments: ["HeatMoment", "-disableDebugProUnlock"],
                    environment: [:]
                )
            )
        }

        func testDebugOverrideCanBeDisabledByEnvironment() {
            XCTAssertFalse(
                SubscriptionDebugOverride.isActive(
                    arguments: ["HeatMoment"],
                    environment: ["HEATMOMENT_DISABLE_DEBUG_PRO_UNLOCK": "1"]
                )
            )
        }

        func testDebugOverrideIsInactiveDuringUnitTests() {
            XCTAssertFalse(
                SubscriptionDebugOverride.isActive(
                    arguments: ["HeatMomentTests"],
                    environment: [
                        "XCTestConfigurationFilePath": "/tmp/HeatMomentTests.xctestconfiguration"
                    ]
                )
            )
        }

        func testDebugOverrideIsInactiveDuringUITests() {
            XCTAssertFalse(
                SubscriptionDebugOverride.isActive(
                    arguments: ["HeatMoment", "-uiTestReset"],
                    environment: [:]
                )
            )
        }

        @MainActor
        func testDebugOverrideDoesNotPersistSubscriptionCache() async {
            let suiteName = "com.heatmoment.tests.subscriptionDebugOverride.\(UUID().uuidString)"
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                XCTFail("无法创建测试 UserDefaults suite")
                return
            }
            defer {
                defaults.removePersistentDomain(forName: suiteName)
            }

            let cacheStore = SubscriptionStateCacheStore(defaults: defaults)
            let service = SubscriptionService(
                cacheStore: cacheStore,
                debugOverrideIsActive: { true }
            )

            XCTAssertTrue(service.isPro)
            let isPro = await service.currentEntitlementIsPro()
            XCTAssertTrue(isPro)
            XCTAssertNil(cacheStore.load())
        }
    }
#endif
