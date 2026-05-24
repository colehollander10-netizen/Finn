import StoreKit

enum SubscriptionTier: String, Sendable {
    case free
    case pro
}

enum FinnProProducts {
    static let monthly = "com.colehollander.subly.pro.monthly"
    static let yearly = "com.colehollander.subly.pro.yearly"
    static let founding = "com.colehollander.subly.pro.founding"

    static let orderedIDs = [monthly, yearly, founding]
    static let allIDs = Set(orderedIDs)

    static func contains(_ productID: String) -> Bool {
        allIDs.contains(productID)
    }

    static func sort(_ products: [Product]) -> [Product] {
        products.sorted {
            guard let lhs = orderedIDs.firstIndex(of: $0.id) else { return false }
            guard let rhs = orderedIDs.firstIndex(of: $1.id) else { return true }
            return lhs < rhs
        }
    }
}
