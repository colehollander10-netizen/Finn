import PhosphorSwift
import StoreKit
import SwiftUI

@MainActor
struct FinnProPaywallView: View {
    @Environment(AppEntitlements.self) private var entitlements

    @State private var selectedPlan: ProPlan = .yearly
    @State private var isPurchasing = false
    @State private var isRestoring = false

    private var availableProducts: [Product] {
        entitlements.products.filter { product in
            FinnProProducts.allIDs.contains(product.id)
        }
    }

    private var productsLoaded: Bool {
        !availableProducts.isEmpty
    }

    private var selectedProduct: Product? {
        product(for: selectedPlan)
    }

    private var hasPro: Bool {
        entitlements.tier == .pro
    }

    var body: some View {
        ScreenFrame {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                        .stagedAppear(0, offset: 10)

                    benefitsCard
                        .stagedAppear(1)

                    planPicker
                        .stagedAppear(2)

                    actionBlock
                        .stagedAppear(3)
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 34)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Ph.sparkle.fill
                    .color(FinnTheme.accent)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                Text("Finn Pro")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(FinnTheme.primaryText)
            }

            Text("Unlock the full subscription toolkit while keeping Finn quiet, local, and fast.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FinnTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var benefitsCard: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                benefitRow(icon: Ph.bellRinging.fill, title: "Smarter renewal alerts", subtitle: "More room to catch upcoming charges before they hit.")
                HairlineDivider().padding(.horizontal, 18)
                benefitRow(icon: Ph.receipt.fill, title: "Deeper tracking", subtitle: "Keep more recurring expenses visible in one calm place.")
                HairlineDivider().padding(.horizontal, 18)
                benefitRow(icon: Ph.lockKey.fill, title: "Private by design", subtitle: "No account, bank connection, or cloud sync required.")
            }
        }
    }

    private var planPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Choose Pro")

            SurfaceCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(ProPlan.allCases.enumerated()), id: \.element) { index, plan in
                        planRow(plan)
                        if index < ProPlan.allCases.count - 1 {
                            HairlineDivider().padding(.horizontal, 18)
                        }
                    }
                }
            }

            productStateMessage
        }
    }

    @ViewBuilder
    private var productStateMessage: some View {
        if let errorMessage = entitlements.errorMessage {
            HStack(alignment: .top, spacing: 8) {
                Ph.warningCircle.fill
                    .color(FinnTheme.urgencyWarning)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)

                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FinnTheme.urgencyWarning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if productsLoaded {
            Text("Prices come from the App Store at checkout.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FinnTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        } else if entitlements.isLoadingProducts {
            HStack(alignment: .top, spacing: 8) {
                ProgressView()
                    .tint(FinnTheme.accent)
                    .scaleEffect(0.82)
                    .accessibilityHidden(true)

                Text("StoreKit prices are still loading. Fallback prices are shown for now.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FinnTheme.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text("StoreKit did not return Pro products yet. Fallback prices are shown until products are available.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FinnTheme.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionBlock: some View {
        VStack(spacing: 12) {
            Button {
                Task { await purchaseSelectedPlan() }
            } label: {
                HStack(spacing: 8) {
                    if isPurchasing {
                        ProgressView()
                            .tint(FinnTheme.background)
                            .accessibilityHidden(true)
                    }
                    Text(primaryButtonTitle)
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(PrimaryButton())
            .disabled(hasPro || selectedProduct == nil || isPurchasing || isRestoring)

            Button {
                Task { await restore() }
            } label: {
                HStack(spacing: 8) {
                    if isRestoring {
                        ProgressView()
                            .tint(FinnTheme.accent)
                            .accessibilityHidden(true)
                    }
                    Text("Restore purchases")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(FinnTheme.accent)
                }
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableRowStyle())
            .disabled(isPurchasing || isRestoring)

            Text("Purchases are handled by Apple. You can change or cancel subscription plans in App Store settings.")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(FinnTheme.tertiaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var primaryButtonTitle: String {
        if hasPro { return "Finn Pro is active" }
        if isPurchasing { return "Starting purchase..." }
        if selectedProduct == nil { return "Loading purchase..." }
        return "Continue with \(selectedPlan.shortTitle)"
    }

    private func benefitRow(icon: Image, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon
                .color(FinnTheme.accent)
                .frame(width: 22, height: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(FinnTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FinnTheme.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
    }

    private func planRow(_ plan: ProPlan) -> some View {
        let isSelected = selectedPlan == plan

        return Button {
            Haptics.play(.rowTap)
            withAnimation(FinnMotion.standard) {
                selectedPlan = plan
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                (isSelected ? Ph.checkCircle.fill : Ph.circle.regular)
                    .color(isSelected ? FinnTheme.accent : FinnTheme.tertiaryText)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(plan.title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(FinnTheme.primaryText)
                        if let badge = plan.badge {
                            Text(badge.uppercased())
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                                .foregroundStyle(FinnTheme.accent)
                                .tracking(0.8)
                        }
                    }

                    Text(plan.subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FinnTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(displayPrice(for: plan))
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(FinnTheme.primaryText)
                        .monospacedDigit()
                    Text(plan.priceCaption)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(FinnTheme.tertiaryText)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
            .background {
                if isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(FinnTheme.accentSoft)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
            }
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityElement(children: .combine)
    }

    private func displayPrice(for plan: ProPlan) -> String {
        product(for: plan)?.displayPrice ?? plan.fallbackPrice
    }

    private func product(for plan: ProPlan) -> Product? {
        availableProducts.first { product in
            product.id == plan.productID
        }
    }

    private func purchaseSelectedPlan() async {
        guard let selectedProduct, !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        Haptics.play(.primaryTap)
        let purchased = await entitlements.purchase(selectedProduct)
        Haptics.play(purchased ? .save : .validationFail)
    }

    private func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        Haptics.play(.rowTap)
        await entitlements.restorePurchases()
        Haptics.play(hasPro ? .save : .validationFail)
    }
}

private enum ProPlan: CaseIterable, Hashable {
    case monthly
    case yearly
    case lifetime

    var title: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .lifetime: return "Founding lifetime"
        }
    }

    var shortTitle: String {
        switch self {
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .lifetime: return "Lifetime"
        }
    }

    var subtitle: String {
        switch self {
        case .monthly:
            return "A flexible way to keep Pro active."
        case .yearly:
            return "Best for keeping Finn set up and out of the way."
        case .lifetime:
            return "One purchase for early supporters."
        }
    }

    var fallbackPrice: String {
        switch self {
        case .monthly: return "$2.99"
        case .yearly: return "$24.99"
        case .lifetime: return "$59"
        }
    }

    var priceCaption: String {
        switch self {
        case .monthly: return "per month"
        case .yearly: return "per year"
        case .lifetime: return "one time"
        }
    }

    var badge: String? {
        switch self {
        case .monthly: return nil
        case .yearly: return "Best value"
        case .lifetime: return "Founding"
        }
    }

    var productID: String {
        switch self {
        case .monthly: return FinnProProducts.monthly
        case .yearly: return FinnProProducts.yearly
        case .lifetime: return FinnProProducts.founding
        }
    }
}
