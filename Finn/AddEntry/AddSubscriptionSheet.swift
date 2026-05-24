import NotificationEngine
import OSLog
import PhosphorSwift
import SubscriptionStore
import SwiftData
import SwiftUI

private let addSubscriptionLog = Logger(subsystem: "com.colehollander.finn", category: "add-subscription")

struct AddSubscriptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(AppEntitlements.self) private var entitlements
    @Query(filter: #Predicate<Trial> { $0.entryTypeRaw == "subscription" && $0.statusRaw == "active" }) private var activeSubscriptions: [Trial]

    var onSave: (Trial) -> Void = { _ in }

    @State private var serviceName: String = ""
    @State private var senderDomain: String = ""
    @State private var chargeDate: Date
    @State private var billingCycle: BillingCycle = .monthly
    @State private var chargeAmountText: String = ""
    @State private var searchQuery: String = ""
    @State private var hasPickedFromCatalog = false
    @State private var isSaving = false
    @State private var showingFinnProPaywall = false
    @State private var saveErrorMessage: String?
    @FocusState private var searchFocused: Bool

    init(onSave: @escaping (Trial) -> Void = { _ in }) {
        self.onSave = onSave
        let in30 = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
        _chargeDate = State(initialValue: in30)
    }

    private var parsedAmount: Decimal? {
        Decimal(string: chargeAmountText.replacingOccurrences(of: "$", with: ""))
    }

    private var canSave: Bool {
        !serviceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && parsedAmount != nil
    }

    private var searchResults: [CatalogService] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return Array(ServicesCatalog.search(trimmed).prefix(8))
    }

    private var showCatalogResults: Bool {
        !searchResults.isEmpty && !hasPickedFromCatalog
    }

    var body: some View {
        NavigationStack {
            ScreenFrame {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        header
                        catalogSearch
                        if showCatalogResults {
                            catalogResultsCard
                        } else {
                            HairlineDivider()
                            fieldsCard
                            Button {
                                save()
                            } label: {
                                HStack(spacing: 8) {
                                    if isSaving {
                                        ProgressView()
                                            .tint(FinnTheme.background)
                                    }
                                    Text(isSaving ? "Saving" : "Save")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(PrimaryButton())
                            .disabled(!canSave || isSaving)
                            .padding(.top, 4)

                            if let saveErrorMessage {
                                Text(saveErrorMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(FinnTheme.urgencyCritical)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(FinnTheme.primaryText)
                    }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingFinnProPaywall) {
            FinnProPaywallView()
        }
    }

    @ViewBuilder
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionLabel(title: "New subscription")
            Text("Add Subscription")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(FinnTheme.primaryText)
        }
    }

    @ViewBuilder
    private var catalogSearch: some View {
        HStack(spacing: 10) {
            Ph.magnifyingGlass.regular
                .color(FinnTheme.tertiaryText)
                .frame(width: 18, height: 18)
            TextField("Search Netflix, Spotify, ChatGPT…", text: $searchQuery)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(FinnTheme.primaryText)
                .focused($searchFocused)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchQuery) { _, newValue in
                    if newValue.isEmpty {
                        hasPickedFromCatalog = false
                    } else if hasPickedFromCatalog && newValue != serviceName {
                        hasPickedFromCatalog = false
                    }
                }
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                    hasPickedFromCatalog = false
                    Haptics.play(.primaryTap)
                } label: {
                    Ph.xCircle.fill
                        .color(FinnTheme.tertiaryText)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(FinnTheme.backgroundElevated)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(FinnTheme.glassBorder, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var catalogResultsCard: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(searchResults.enumerated()), id: \.element.id) { index, service in
                    Button {
                        applyCatalog(service)
                    } label: {
                        catalogResultRow(service)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(PressableRowStyle())
                    if index < searchResults.count - 1 {
                        HairlineDivider().padding(.horizontal, 14)
                    }
                }

                HairlineDivider()

                Button {
                    useCustomService()
                } label: {
                    HStack(spacing: 12) {
                        Ph.plusCircle.regular
                            .color(FinnTheme.accent)
                            .frame(width: 22, height: 22)
                        Text("Add \"\(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines))\" as custom")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(FinnTheme.primaryText)
                            .lineLimit(1)
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PressableRowStyle())
            }
        }
    }

    @ViewBuilder
    private func catalogResultRow(_ service: CatalogService) -> some View {
        HStack(spacing: 12) {
            ServiceIcon(name: service.name, domain: service.domain, size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FinnTheme.primaryText)
                Text("\(service.category) · \(formatUSD(service.suggestedPriceDecimal))/\(billingCycleSuffix(for: service.billingCycleEnum))")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FinnTheme.tertiaryText)
                    .monospacedDigit()
            }
            Spacer()
            Ph.caretRight.bold
                .color(FinnTheme.tertiaryText)
                .frame(width: 12, height: 12)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var fieldsCard: some View {
        SurfaceCard(padding: 0) {
            VStack(spacing: 0) {
                ServiceNameField(text: $serviceName, label: "Service", placeholder: "Netflix")
                HairlineDivider().padding(.leading, 54)
                DatePickerField(date: $chargeDate, label: "Next billing date")
                HairlineDivider().padding(.leading, 54)
                billingCycleField
                HairlineDivider().padding(.leading, 54)
                AmountField(text: $chargeAmountText, label: "Charge amount", placeholder: "9.99")
            }
        }
    }

    @ViewBuilder
    private var billingCycleField: some View {
        FieldRow(
            icon: AnyView(Ph.repeat.regular.color(FinnTheme.tertiaryText).frame(width: 22, height: 22)),
            label: "Billing cycle"
        ) {
            Picker("", selection: $billingCycle) {
                Text("Monthly").tag(BillingCycle.monthly)
                Text("Yearly").tag(BillingCycle.yearly)
                Text("Weekly").tag(BillingCycle.weekly)
                Text("Custom").tag(BillingCycle.custom)
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .onChange(of: billingCycle) { _, _ in
                Haptics.play(.primaryTap)
            }
        }
    }

    private func applyCatalog(_ service: CatalogService) {
        serviceName = service.name
        senderDomain = service.domain
        billingCycle = service.billingCycleEnum
        chargeAmountText = String(format: "%.2f", service.suggestedPrice)
        searchQuery = service.name
        hasPickedFromCatalog = true
        searchFocused = false
        Haptics.play(.primaryTap)
    }

    private func useCustomService() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        serviceName = trimmed
        senderDomain = ""
        hasPickedFromCatalog = true
        searchFocused = false
        Haptics.play(.primaryTap)
    }

    private func billingCycleSuffix(for cycle: BillingCycle) -> String {
        switch cycle {
        case .monthly: return "mo"
        case .yearly: return "yr"
        case .weekly: return "wk"
        case .custom: return "period"
        }
    }

    private func save() {
        let trimmed = serviceName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !isSaving else { return }
        guard !trimmed.isEmpty else { return }
        guard let amount = parsedAmount else { return }
        if entitlements.tier == .free && activeSubscriptions.count >= 10 {
            showingFinnProPaywall = true
            Haptics.play(.validationFail)
            return
        }
        isSaving = true
        saveErrorMessage = nil
        let entry = Trial(
            serviceName: trimmed,
            senderDomain: senderDomain,
            chargeDate: chargeDate,
            chargeAmount: amount,
            entryType: .subscription,
            status: .active,
            billingCycle: billingCycle,
            notificationOffset: nil
        )
        modelContext.insert(entry)
        do {
            try modelContext.save()
        } catch {
            modelContext.delete(entry)
            addSubscriptionLog.error("Subscription save failed: \(String(describing: error), privacy: .public)")
            saveErrorMessage = "Could not save. Try again."
            isSaving = false
            Haptics.play(.validationFail)
            return
        }
        Haptics.play(.save)

        let container = modelContext.container
        Task {
            let coordinator = TrialAlertCoordinator(
                modelContainer: container,
                notificationEngine: NotificationEngine()
            )
            await coordinator.replanAll()
        }

        onSave(entry)
        withAnimation(FinnMotion.sheet) {
            dismiss()
        }
    }
}

#Preview {
    if let container = try? ModelContainer(
        for: Schema([Trial.self]),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true)
    ) {
        ZStack {
            FinnTheme.background.ignoresSafeArea()
            AddSubscriptionSheet()
        }
        .modelContainer(container)
    } else {
        Text("Preview unavailable")
    }
}
