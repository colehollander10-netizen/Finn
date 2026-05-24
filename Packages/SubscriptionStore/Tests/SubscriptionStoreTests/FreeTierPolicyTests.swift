import XCTest
@testable import SubscriptionStore

final class FreeTierPolicyTests: XCTestCase {
    // MARK: - Limits

    func testLimitsMatchProductSpec() {
        // Arrange / Act / Assert — these numbers are the monetization contract.
        XCTAssertEqual(FreeTierPolicy.freeTrialLimit, 3)
        XCTAssertEqual(FreeTierPolicy.subscriptionLimit, 10)
        XCTAssertEqual(FreeTierPolicy.limit(for: .freeTrial), 3)
        XCTAssertEqual(FreeTierPolicy.limit(for: .subscription), 10)
    }

    // MARK: - Free tier, under the cap

    func testFreeUserUnderTrialCapIsAllowed() {
        let decision = FreeTierPolicy.decision(for: .freeTrial, currentActiveCount: 2, isPro: false)
        XCTAssertEqual(decision, .allowed)
    }

    func testFreeUserUnderSubscriptionCapIsAllowed() {
        let decision = FreeTierPolicy.decision(for: .subscription, currentActiveCount: 9, isPro: false)
        XCTAssertEqual(decision, .allowed)
    }

    // MARK: - Free tier, at / over the cap

    func testFreeUserAtTrialCapIsBlocked() {
        let decision = FreeTierPolicy.decision(for: .freeTrial, currentActiveCount: 3, isPro: false)
        XCTAssertEqual(decision, .blocked(limit: 3))
    }

    func testFreeUserAtSubscriptionCapIsBlocked() {
        let decision = FreeTierPolicy.decision(for: .subscription, currentActiveCount: 10, isPro: false)
        XCTAssertEqual(decision, .blocked(limit: 10))
    }

    func testFreeUserOverCapStaysBlocked() {
        // Defends against the share-extension bypass that historically let
        // counts drift above the cap — once over, still blocked.
        let decision = FreeTierPolicy.decision(for: .subscription, currentActiveCount: 25, isPro: false)
        XCTAssertEqual(decision, .blocked(limit: 10))
    }

    // MARK: - Pro tier is unlimited

    func testProUserIsAlwaysAllowed() {
        XCTAssertEqual(FreeTierPolicy.decision(for: .freeTrial, currentActiveCount: 999, isPro: true), .allowed)
        XCTAssertEqual(FreeTierPolicy.decision(for: .subscription, currentActiveCount: 999, isPro: true), .allowed)
    }

    // MARK: - Trials and subscriptions are counted independently

    func testTrialCapDoesNotAffectSubscriptions() {
        // 3 active trials (at trial cap) does not block a subscription.
        let subDecision = FreeTierPolicy.decision(for: .subscription, currentActiveCount: 0, isPro: false)
        XCTAssertEqual(subDecision, .allowed)
    }

    // MARK: - canAdd convenience

    func testCanAddMirrorsDecision() {
        XCTAssertTrue(FreeTierPolicy.canAdd(.freeTrial, currentActiveCount: 0, isPro: false))
        XCTAssertFalse(FreeTierPolicy.canAdd(.freeTrial, currentActiveCount: 3, isPro: false))
        XCTAssertTrue(FreeTierPolicy.canAdd(.freeTrial, currentActiveCount: 3, isPro: true))
    }

    // MARK: - remaining (drives proactive UI)

    func testRemainingCountsDownToZero() {
        XCTAssertEqual(FreeTierPolicy.remaining(for: .freeTrial, currentActiveCount: 0, isPro: false), 3)
        XCTAssertEqual(FreeTierPolicy.remaining(for: .freeTrial, currentActiveCount: 2, isPro: false), 1)
        XCTAssertEqual(FreeTierPolicy.remaining(for: .freeTrial, currentActiveCount: 3, isPro: false), 0)
    }

    func testRemainingNeverNegativeWhenOverCap() {
        XCTAssertEqual(FreeTierPolicy.remaining(for: .subscription, currentActiveCount: 15, isPro: false), 0)
    }

    func testRemainingIsNilForPro() {
        XCTAssertNil(FreeTierPolicy.remaining(for: .subscription, currentActiveCount: 5, isPro: true))
    }

    // MARK: - planBatch (the share-extension gate path)

    func testPlanBatchFreeUserAtTrialCapSkipsAll() {
        // Free user already at the 3-trial cap; both shared trials are dropped.
        let admissions = FreeTierPolicy.planBatch(
            candidateTypes: [.freeTrial, .freeTrial],
            seedActiveCounts: [.freeTrial: 3],
            isPro: false
        )
        XCTAssertEqual(admissions, [false, false])
    }

    func testPlanBatchConsumesSlotsWithinSameBatch() {
        // 2 active trials, 3 incoming: first accepted (→3), next two blocked.
        let admissions = FreeTierPolicy.planBatch(
            candidateTypes: [.freeTrial, .freeTrial, .freeTrial],
            seedActiveCounts: [.freeTrial: 2],
            isPro: false
        )
        XCTAssertEqual(admissions, [true, false, false])
    }

    func testPlanBatchCountsTypesIndependently() {
        // At trial cap but no subscriptions — the subscription still goes in.
        let admissions = FreeTierPolicy.planBatch(
            candidateTypes: [.freeTrial, .subscription],
            seedActiveCounts: [.freeTrial: 3, .subscription: 0],
            isPro: false
        )
        XCTAssertEqual(admissions, [false, true])
    }

    func testPlanBatchProUserAdmitsEverything() {
        let admissions = FreeTierPolicy.planBatch(
            candidateTypes: [.freeTrial, .freeTrial, .subscription, .subscription],
            seedActiveCounts: [.freeTrial: 99, .subscription: 99],
            isPro: true
        )
        XCTAssertEqual(admissions, [true, true, true, true])
    }

    func testPlanBatchEmptyInput() {
        XCTAssertEqual(FreeTierPolicy.planBatch(candidateTypes: [], seedActiveCounts: [:], isPro: false), [])
    }
}
