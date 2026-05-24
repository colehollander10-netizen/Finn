import Foundation

/// Single source of truth for what the free tier allows. The two limits used to
/// live as bare `>= 3` / `>= 10` literals scattered across `AddSubscriptionSheet`
/// and `TrialDetailSheet`; centralizing them here means the paywall, the gates,
/// and the share-extension importer all agree on one number.
///
/// Pure value type with no StoreKit dependency — callers pass a plain `isPro`
/// flag (mapped from `AppEntitlements.tier` in the app layer). This keeps the
/// package testable without a StoreKit harness.
public enum FreeTierPolicy {
    /// Max *active* free trials a free-tier user may track at once.
    public static let freeTrialLimit = 3

    /// Max *active* subscriptions a free-tier user may track at once.
    public static let subscriptionLimit = 10

    /// The active-entry cap for a given entry type on the free tier.
    public static func limit(for entryType: EntryType) -> Int {
        switch entryType {
        case .freeTrial: return freeTrialLimit
        case .subscription: return subscriptionLimit
        }
    }

    /// Decide whether a new entry of `entryType` may be saved.
    ///
    /// - Parameters:
    ///   - entryType: the kind of entry being added.
    ///   - currentActiveCount: how many *active* entries of that type already exist.
    ///   - isPro: whether the user holds the Pro entitlement.
    public static func decision(
        for entryType: EntryType,
        currentActiveCount: Int,
        isPro: Bool
    ) -> Decision {
        guard !isPro else { return .allowed }
        let cap = limit(for: entryType)
        return currentActiveCount >= cap ? .blocked(limit: cap) : .allowed
    }

    /// Convenience boolean for call sites that only care about the yes/no.
    public static func canAdd(
        _ entryType: EntryType,
        currentActiveCount: Int,
        isPro: Bool
    ) -> Bool {
        decision(for: entryType, currentActiveCount: currentActiveCount, isPro: isPro).isAllowed
    }

    /// How many more active entries of `entryType` a free user may add before
    /// hitting the cap. `nil` when unlimited (Pro). Used to drive the
    /// "X of Y used" / "1 slot left" proactive UI before the hard block.
    public static func remaining(
        for entryType: EntryType,
        currentActiveCount: Int,
        isPro: Bool
    ) -> Int? {
        guard !isPro else { return nil }
        return max(0, limit(for: entryType) - currentActiveCount)
    }

    /// Plan a batch of candidate inserts against the free-tier caps, given the
    /// active counts already in the store. Returns, for each candidate (by
    /// index), whether it would be accepted — accounting for earlier accepted
    /// candidates in the same batch consuming slots.
    ///
    /// Pulled out of `SharedCaptureImporter` so the share-extension gate is
    /// unit-testable without a live `ModelContext`. The importer maps `true`
    /// → insert, `false` → drop + count as skipped.
    public static func planBatch(
        candidateTypes: [EntryType],
        seedActiveCounts: [EntryType: Int],
        isPro: Bool
    ) -> [Bool] {
        var running = seedActiveCounts
        return candidateTypes.map { type in
            let allowed = canAdd(type, currentActiveCount: running[type, default: 0], isPro: isPro)
            if allowed { running[type, default: 0] += 1 }
            return allowed
        }
    }

    /// Outcome of a gate check.
    public enum Decision: Equatable, Sendable {
        case allowed
        /// Save refused; `limit` is the cap that was hit (for UI copy).
        case blocked(limit: Int)

        public var isAllowed: Bool {
            if case .allowed = self { return true }
            return false
        }
    }
}
