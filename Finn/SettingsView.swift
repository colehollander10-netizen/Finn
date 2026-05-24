import NotificationEngine
import OSLog
import PhosphorSwift
import SubscriptionStore
import SwiftData
import SwiftUI
import UIKit
import UserNotifications

private let settingsLog = Logger(subsystem: "com.colehollander.finn", category: "settings")

@MainActor
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AutoImportService.self) private var autoImportService
    @Environment(AppEntitlements.self) private var entitlements

    @Query private var allTrials: [Trial]
    @State private var errorMessage: String?
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isUpdatingNotifications = false
    @State private var isFetchingImport = false
    @State private var lastAppleSync: Date? = UserDefaults.standard.object(forKey: "lastAppleSync") as? Date
    @State private var exportedCSVURL: URL?
    @State private var showingDeleteConfirm = false
    @State private var showingFinnProPaywall = false
    @State private var importSheetPayload: ImportSheetPayload?

    var body: some View {
        NavigationStack {
            ScreenFrame {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Notifications", trailing: notificationStatusLabel)
                            SurfaceCard(padding: 18) {
                                VStack(alignment: .leading, spacing: 14) {
                                    Text(notificationSummary)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(FinnTheme.secondaryText)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Button {
                                        Task {
                                            Haptics.play(.primaryTap)
                                            await handleNotificationAction()
                                        }
                                    } label: {
                                        HStack {
                                            if isUpdatingNotifications {
                                                ProgressView().tint(FinnTheme.background)
                                            }
                                            Text(notificationActionTitle).frame(maxWidth: .infinity)
                                        }
                                    }
                                    .buttonStyle(PrimaryButton())
                                    .disabled(isUpdatingNotifications)

                                    if let errorMessage {
                                        Text(errorMessage)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundStyle(FinnTheme.urgencyCritical)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Finn Pro", trailing: entitlements.tier == .pro ? "Active" : "$2.99/mo")
                            SurfaceCard(padding: 0) {
                                settingsRow(
                                    title: entitlements.tier == .pro ? "You're a Pro" : "Upgrade to Pro",
                                    subtitle: entitlements.tier == .pro ? "Finn Pro is active on this device." : "Unlimited entries, founding lifetime option, and the full Finn toolkit.",
                                    tint: FinnTheme.primaryText
                                ) {
                                    Haptics.play(.rowTap)
                                    if entitlements.tier == .pro {
                                        Task { await entitlements.restorePurchases() }
                                    } else {
                                        showingFinnProPaywall = true
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "Data")
                            SurfaceCard(padding: 0) {
                                VStack(spacing: 0) {
                                    settingsRow(title: "Sync now", subtitle: "Auto-sync is on for Apple subscriptions.", tint: FinnTheme.primaryText) {
                                        Haptics.play(.rowTap)
                                        Task { await runAppleSync() }
                                    }
                                    .disabled(isFetchingImport || autoImportService.isSyncing)
                                    syncStatusBlock
                                    HairlineDivider().padding(.horizontal, 18)
                                    settingsRow(title: "Choose what to import", subtitle: "Pick which Apple subscriptions Finn should track.", tint: FinnTheme.primaryText) {
                                        Haptics.play(.rowTap)
                                        Task { await presentImportSheet() }
                                    }
                                    .disabled(isFetchingImport || autoImportService.isSyncing)
                                    HairlineDivider().padding(.horizontal, 18)
                                    settingsRow(title: "Export trials", subtitle: "Share a CSV of every trial on this device.", tint: FinnTheme.primaryText) {
                                        Haptics.play(.rowTap)
                                        exportTrials()
                                    }
                                    HairlineDivider().padding(.horizontal, 18)
                                    settingsRow(title: "Delete all data", subtitle: "Wipe every trial from this device. This cannot be undone.", tint: FinnTheme.urgencyCritical) {
                                        Haptics.play(.rowTap)
                                        showingDeleteConfirm = true
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            SectionLabel(title: "About")
                            SurfaceCard(padding: 18) {
                                VStack(alignment: .leading, spacing: 14) {
                                    HStack {
                                        Text("Version")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(FinnTheme.primaryText)
                                        Spacer()
                                        Text(appVersion)
                                            .font(.system(size: 15, weight: .medium, design: .rounded))
                                            .monospacedDigit()
                                            .foregroundStyle(FinnTheme.secondaryText)
                                    }
                                    HairlineDivider()
                                    Button {
                                        Haptics.play(.rowTap)
                                        if let url = URL(string: "https://finn.app/privacy") {
                                            UIApplication.shared.open(url)
                                        }
                                    } label: {
                                        HStack {
                                            Text("Privacy policy")
                                                .font(.system(size: 15, weight: .medium))
                                                .foregroundStyle(FinnTheme.primaryText)
                                            Spacer()
                                            Ph.arrowUpRight.bold
                                                .color(FinnTheme.tertiaryText)
                                                .frame(width: 14, height: 14)
                                        }
                                        .contentShape(Rectangle())
                                    }
                                    .buttonStyle(PressableRowStyle())
                                }
                            }
                        }
                    }
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
                }
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .principal) {
                        Text("Settings")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(FinnTheme.primaryText)
                    }
                }
            }
        }
        .confirmationDialog("Delete all trials?", isPresented: $showingDeleteConfirm, titleVisibility: .visible) {
            Button("Delete all", role: .destructive) {
                Haptics.play(.destructiveConfirm)
                deleteAllData()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes every trial from this device. Cannot be undone.")
        }
        .sheet(item: $exportedCSVURL) { url in
            ShareSheet(activityItems: [url])
        }
        .sheet(isPresented: $showingFinnProPaywall) {
            FinnProPaywallView()
        }
        .onChange(of: exportedCSVURL?.id) { _, newValue in
            if newValue != nil { Haptics.play(.sheetPresent) }
        }
        .sheet(item: $importSheetPayload) { payload in
            ImportConfirmationSheet(subscriptions: payload.subscriptions) { chosen in
                Task { await runSelectiveImport(chosen) }
            }
        }
        .onChange(of: importSheetPayload?.id) { _, newValue in
            if newValue != nil { Haptics.play(.sheetPresent) }
        }
        .overlay {
            if isFetchingImport {
                ZStack {
                    FinnTheme.background.opacity(0.6).ignoresSafeArea()
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(FinnTheme.accent)
                }
                .transition(.opacity)
            }
        }
        .task {
            await refreshNotificationStatus()
            lastAppleSync = UserDefaults.standard.object(forKey: "lastAppleSync") as? Date
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await refreshNotificationStatus()
                lastAppleSync = UserDefaults.standard.object(forKey: "lastAppleSync") as? Date
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(version) (\(build))"
    }

    private var lastAppleSyncText: String {
        if let lastAppleSync {
            return "Last synced: \(lastAppleSync.formatted(date: .abbreviated, time: .shortened))"
        }

        return "Last synced: Never"
    }

    /// Renders the most recent sync outcome under the "Sync now" row.
    /// Falls back to the persisted `lastAppleSync` timestamp when the
    /// in-memory summary hasn't populated yet (e.g. fresh launch + Settings
    /// opened before any sync ran).
    @ViewBuilder
    private var syncStatusBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(lastAppleSyncText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FinnTheme.tertiaryText)
            if isFetchingImport || autoImportService.isSyncing {
                Text("Checking Apple subscriptions...")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FinnTheme.secondaryText)
            }
            if let summary = autoImportService.lastSummary {
                if let saveError = summary.saveError {
                    Text("Save failed: \(saveError)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FinnTheme.urgencyCritical)
                } else if let fetchError = summary.fetchError {
                    Text("Apple lookup failed: \(fetchError)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(FinnTheme.urgencyCritical)
                } else {
                    Text(summaryDetailText(for: summary))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FinnTheme.secondaryText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
    }

    private func summaryDetailText(for summary: ImportSummary) -> String {
        var parts: [String] = []
        if summary.inserted > 0 { parts.append("Imported \(summary.inserted)") }
        if summary.updated > 0 { parts.append("Updated \(summary.updated)") }
        if !summary.skipped.isEmpty { parts.append("Skipped \(summary.skipped.count)") }
        if parts.isEmpty {
            return "No App Store subscriptions found."
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func presentImportSheet() async {
        guard !isFetchingImport else { return }
        isFetchingImport = true
        defer { isFetchingImport = false }
        let subs = await StoreKitImport.fetchCurrent()
        importSheetPayload = ImportSheetPayload(subscriptions: subs)
    }

    @MainActor
    private func runSelectiveImport(_ chosen: [ImportableSubscription]) async {
        guard !chosen.isEmpty, !isFetchingImport else { return }
        isFetchingImport = true
        defer { isFetchingImport = false }
        _ = await autoImportService.importChosen(chosen, context: modelContext)
        lastAppleSync = UserDefaults.standard.object(forKey: "lastAppleSync") as? Date
        Haptics.play(.save)
    }

    @ViewBuilder
    private func settingsRow(title: String, subtitle: String, tint: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(tint)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FinnTheme.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Ph.caretRight.bold
                    .color(FinnTheme.tertiaryText)
                    .frame(width: 12, height: 12)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle())
    }

    @MainActor
    private func runAppleSync() async {
        guard !isFetchingImport else { return }
        isFetchingImport = true
        defer { isFetchingImport = false }

        await autoImportService.sync(context: modelContext)
        lastAppleSync = UserDefaults.standard.object(forKey: "lastAppleSync") as? Date
        Haptics.play(.save)
    }

    private func exportTrials() {
        errorMessage = nil
        let header = "Service,End Date,Charge Amount\n"
        let rows = allTrials.map { trial -> String in
            let service = trial.serviceName.replacingOccurrences(of: ",", with: " ")
            let date = ISO8601DateFormatter().string(from: trial.chargeDate)
            let amount = trial.chargeAmount.map { "\($0)" } ?? ""
            return "\(service),\(date),\(amount)"
        }.joined(separator: "\n")
        let csv = header + rows
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("finn-trials.csv")
        do {
            try csv.data(using: .utf8)?.write(to: url)
        } catch {
            settingsLog.error("CSV export failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Could not export your data. Try again."
            Haptics.play(.validationFail)
            return
        }
        exportedCSVURL = url
    }

    private func deleteAllData() {
        errorMessage = nil
        for trial in allTrials {
            modelContext.delete(trial)
        }
        do {
            try modelContext.save()
        } catch {
            settingsLog.error("Delete all data failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Could not delete data. Try again."
            Haptics.play(.validationFail)
            return
        }
        Haptics.play(.destructiveConfirm)
        let container = modelContext.container
        Task {
            let coordinator = TrialAlertCoordinator(
                modelContainer: container,
                notificationEngine: NotificationEngine()
            )
            await coordinator.replanAll()
        }
    }

    private var notificationStatusLabel: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "On"
        case .denied:
            return "Off"
        case .notDetermined:
            return "Setup"
        @unknown default:
            return "Unknown"
        }
    }

    private var notificationSummary: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Finn will remind you before a trial charges and can send a follow-up nudge if you put cancellation off."
        case .denied:
            return "Alerts are off right now. Turn them back on in iPhone Settings so Finn can warn you before a free trial bills your card."
        case .notDetermined:
            return "Turn on alerts so Finn can catch upcoming charges in time and follow up if you meant to cancel later."
        @unknown default:
            return "Finn uses notifications to warn you before trial charges land."
        }
    }

    private var notificationActionTitle: String {
        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Refresh alerts"
        case .denied:
            return "Open iPhone Settings"
        case .notDetermined:
            return "Enable notifications"
        @unknown default:
            return "Check notifications"
        }
    }

    @MainActor
    private func refreshNotificationStatus() async {
        notificationStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    @MainActor
    private func handleNotificationAction() async {
        errorMessage = nil
        isUpdatingNotifications = true
        defer { isUpdatingNotifications = false }

        switch notificationStatus {
        case .authorized, .provisional, .ephemeral:
            let coordinator = TrialAlertCoordinator(
                modelContainer: modelContext.container,
                notificationEngine: NotificationEngine()
            )
            await coordinator.replanAll()

        case .notDetermined:
            let granted = await NotificationEngine().requestAuthorization()
            await refreshNotificationStatus()
            if granted || notificationStatus == .authorized {
                let coordinator = TrialAlertCoordinator(
                    modelContainer: modelContext.container,
                    notificationEngine: NotificationEngine()
                )
                await coordinator.replanAll()
            }

        case .denied:
            guard let url = URL(string: UIApplication.openSettingsURLString) else { break }
            _ = await UIApplication.shared.open(url)

        @unknown default:
            await refreshNotificationStatus()
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// Wraps the StoreKit fetch result so SwiftUI's `.sheet(item:)` can drive
/// presentation off a single Optional. Identity is just the row count + a
/// timestamp because the sheet should re-present every time the user taps
/// "Choose what to import," even if Apple returned the same products.
private struct ImportSheetPayload: Identifiable, Equatable {
    let id = UUID()
    let subscriptions: [ImportableSubscription]
}
