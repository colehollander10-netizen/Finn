import Foundation
import OSLog
import SubscriptionStore
import SwiftData
import TrialParsingCore

private let shareCaptureLog = Logger(subsystem: "com.colehollander.finn", category: "share-capture")

@MainActor
enum SharedCaptureImporter {
    /// Import any captures handed off from the share extension.
    ///
    /// Free-tier limits are enforced here as well as in the in-app add sheets —
    /// otherwise a free user at the cap could keep adding entries by sharing
    /// from outside Finn, bypassing the gate entirely. Over-cap captures are
    /// dropped (the handoff store is a queue, not a persistent inbox) and
    /// reported via `skippedAtLimit` so the app can nudge an upgrade.
    ///
    /// - Parameter isPro: whether the user holds the Pro entitlement. Callers
    ///   must ensure entitlements are resolved (`AppEntitlements.refresh()`)
    ///   before invoking on cold launch, or a Pro user can be wrongly capped.
    static func importPendingEntries(context: ModelContext, isPro: Bool) -> ImportResult {
        let entries: [PendingShareEntry]
        do {
            entries = try ShareHandoffStore.pendingEntries()
        } catch {
            shareCaptureLog.error("Could not read pending share entries: \(String(describing: error), privacy: .public)")
            return .empty
        }

        guard !entries.isEmpty else { return .empty }

        // Parse first so the gate sees only entries that would actually become
        // a Trial — entries with no parse signal are dropped, not counted
        // against the cap. Then plan the whole batch against the free-tier caps
        // via the unit-tested `FreeTierPolicy.planBatch`, seeded from the store.
        var processedIDs: Set<UUID> = []
        let candidates: [(entry: PendingShareEntry, trial: Trial)] = entries.compactMap { entry in
            guard let trial = makeTrial(from: entry) else {
                shareCaptureLog.info("Ignored pending share entry with insufficient parse signal: \(entry.id.uuidString, privacy: .public)")
                processedIDs.insert(entry.id)
                return nil
            }
            return (entry, trial)
        }

        let admissions = FreeTierPolicy.planBatch(
            candidateTypes: candidates.map(\.trial.entryType),
            seedActiveCounts: currentActiveCounts(context: context),
            isPro: isPro
        )

        var importedEntries: [ImportedShareEntry] = []
        var skippedAtLimit = 0
        for (candidate, admitted) in zip(candidates, admissions) {
            processedIDs.insert(candidate.entry.id)
            if admitted {
                context.insert(candidate.trial)
                importedEntries.append(ImportedShareEntry(trial: candidate.trial))
            } else {
                shareCaptureLog.info("Skipped share capture at free-tier limit: \(candidate.entry.id.uuidString, privacy: .public)")
                skippedAtLimit += 1
            }
        }

        guard !importedEntries.isEmpty else {
            removeProcessedPendingEntries(processedIDs)
            return ImportResult(imported: [], skippedAtLimit: skippedAtLimit)
        }

        do {
            try context.save()
            removeProcessedPendingEntries(processedIDs)
            return ImportResult(imported: importedEntries, skippedAtLimit: skippedAtLimit)
        } catch {
            shareCaptureLog.error("Could not save pending share entries: \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    /// Count of active entries per type already in the store, used to seed the
    /// free-tier limit check.
    private static func currentActiveCounts(context: ModelContext) -> [EntryType: Int] {
        let descriptor = FetchDescriptor<Trial>(
            predicate: #Predicate { $0.statusRaw == "active" }
        )
        guard let active = try? context.fetch(descriptor) else { return [:] }
        return Dictionary(grouping: active, by: { $0.entryType }).mapValues(\.count)
    }

    private static func makeTrial(from entry: PendingShareEntry) -> Trial? {
        switch entry.kind {
        case .freeTrial:
            return makeFreeTrial(from: entry)
        case .subscription:
            return makeSubscription(from: entry)
        }
    }

    private static func makeFreeTrial(from entry: PendingShareEntry) -> Trial? {
        let extracted = PastedTrialExtractor.extract(from: entry.recognizedText, source: .screenshot)
        guard let serviceName = extracted.serviceName,
              let chargeDate = extracted.trialEndDate else {
            return nil
        }

        return Trial(
            serviceName: serviceName,
            senderDomain: BrandDirectory.logoDomain(for: serviceName, senderDomain: nil) ?? "",
            chargeDate: chargeDate,
            chargeAmount: extracted.chargeAmount.flatMap { Decimal(string: $0) },
            detectedAt: entry.createdAt,
            entryType: .freeTrial
        )
    }

    private static func makeSubscription(from entry: PendingShareEntry) -> Trial? {
        let fields = TrialParser.extractSubscriptionFields(
            entry.recognizedText,
            now: entry.createdAt,
            source: .screenshot
        )
        guard let serviceName = normalizedServiceName(fields.serviceName),
              let chargeDate = fields.nextChargeDate ?? fallbackChargeDate(from: entry.createdAt),
              fields.chargeAmount != nil || fields.nextChargeDate != nil else {
            return nil
        }

        return Trial(
            serviceName: serviceName,
            senderDomain: BrandDirectory.logoDomain(for: serviceName, senderDomain: nil) ?? "",
            chargeDate: chargeDate,
            chargeAmount: fields.chargeAmount,
            detectedAt: entry.createdAt,
            entryType: .subscription,
            billingCycle: billingCycle(from: fields.billingCycle) ?? .monthly
        )
    }

    private static func normalizedServiceName(_ name: String?) -> String? {
        guard let name else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != "Unknown" else { return nil }
        return trimmed
    }

    private static func fallbackChargeDate(from date: Date) -> Date? {
        Calendar.current.date(byAdding: .month, value: 1, to: date)
    }

    private static func billingCycle(from parsed: SubscriptionBillingCycle?) -> BillingCycle? {
        switch parsed {
        case .monthly:
            return .monthly
        case .yearly:
            return .yearly
        case .weekly:
            return .weekly
        case .custom:
            return .custom
        case .none:
            return nil
        }
    }

    private static func removeProcessedPendingEntries(_ ids: Set<UUID>) {
        guard !ids.isEmpty else { return }
        do {
            try ShareHandoffStore.removePendingEntries(ids: ids)
        } catch {
            shareCaptureLog.error("Could not clear processed share entries: \(String(describing: error), privacy: .public)")
        }
    }
}

/// Outcome of a share-extension import pass: what landed, and how many captures
/// were dropped because the free-tier limit was hit (drives the upgrade nudge).
struct ImportResult: Equatable {
    let imported: [ImportedShareEntry]
    let skippedAtLimit: Int

    static let empty = ImportResult(imported: [], skippedAtLimit: 0)
}

struct ImportedShareEntry: Equatable, Identifiable {
    let id: UUID
    let entryType: EntryType
    let serviceName: String
    let chargeDate: Date
    let chargeAmount: Decimal?

    init(trial: Trial) {
        self.id = trial.id
        self.entryType = trial.entryType
        self.serviceName = trial.serviceName
        self.chargeDate = trial.chargeDate
        self.chargeAmount = trial.chargeAmount
    }
}
