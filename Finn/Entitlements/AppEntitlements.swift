import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class AppEntitlements {
    private(set) var tier: SubscriptionTier = .free
    private(set) var products: [Product] = []
    private(set) var activeProductIDs: Set<String> = []
    private(set) var isLoadingProducts = false
    var errorMessage: String?

    @ObservationIgnored private var updatesTask: Task<Void, Never>?

    deinit {
        updatesTask?.cancel()
    }

    func start() {
        guard updatesTask == nil else { return }

        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.handle(update)
            }
        }

        Task { await refresh() }
    }

    func refresh() async {
        await loadProducts()
        await refreshCurrentEntitlements()
    }

    @discardableResult
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    errorMessage = "We could not verify that purchase."
                    return false
                }
                await transaction.finish()
                await refreshCurrentEntitlements()
                return tier == .pro
            case .pending, .userCancelled:
                return false
            @unknown default:
                return false
            }
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshCurrentEntitlements()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func isActive(_ product: Product) -> Bool {
        activeProductIDs.contains(product.id)
    }

    private func loadProducts() async {
        isLoadingProducts = true
        defer { isLoadingProducts = false }

        do {
            products = FinnProProducts.sort(try await Product.products(for: FinnProProducts.orderedIDs))
            errorMessage = nil
        } catch {
            products = []
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCurrentEntitlements() async {
        var activeIDs = Set<String>()

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            guard FinnProProducts.contains(transaction.productID) else { continue }
            guard transaction.revocationDate == nil else { continue }
            activeIDs.insert(transaction.productID)
        }

        activeProductIDs = activeIDs
        tier = activeIDs.isEmpty ? .free : .pro
    }

    private func handle(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let transaction) = update else { return }
        guard FinnProProducts.contains(transaction.productID) else { return }

        await refreshCurrentEntitlements()
        await transaction.finish()
    }
}
