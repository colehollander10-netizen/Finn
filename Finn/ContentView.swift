import Observation
import NotificationEngine
import PhosphorSwift
import SubscriptionStore
import SwiftData
import SwiftUI
import UIKit

enum AppPreferences {
    static let showDemoData = "showDemoData"
}

/// Typed route used when a notification is tapped. Keeps tab + detail-sheet
/// selection in sync with the entry type the user was alerted about.
enum PendingNotificationRoute: Equatable {
    case trial(UUID)
    case subscription(UUID)

    var entryID: UUID {
        switch self {
        case .trial(let id), .subscription(let id):
            return id
        }
    }
}

@MainActor
@Observable
final class AppRouter {
    /// Legacy compat — mirrored from `pendingRoute` when the route targets a
    /// trial so existing HomeView code keeps working. New callers should
    /// observe `pendingRoute`.
    var pendingCancelTrialID: UUID?
    var pendingRoute: PendingNotificationRoute?
    var pendingSharedTrialText: String?
    var pendingShareConfirmation: ImportedShareEntry?

    /// Number of share-extension captures dropped because the free-tier limit
    /// was hit on the last import pass. Drives the "upgrade to keep them"
    /// nudge toast. `0` means nothing to show.
    var pendingLimitNudgeCount: Int = 0
    /// Set when the user taps the limit nudge — the root view presents the paywall.
    var presentingLimitPaywall = false

    func handle(url: URL) -> Bool {
        guard url.scheme == "finn" else { return false }
        guard url.host == "shared-trial" else { return false }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let text = components?.queryItems?.first(where: { $0.name == "text" })?.value,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }

        pendingSharedTrialText = text
        return true
    }

    func showShareImportResult(_ result: ImportResult) {
        if let entry = result.imported.last {
            pendingShareConfirmation = entry
        }
        if result.skippedAtLimit > 0 {
            // Accumulate across rapid successive imports so the nudge count
            // reflects the true number of dropped captures, not just the last pass.
            pendingLimitNudgeCount += result.skippedAtLimit
        }
    }

    func openShareConfirmation(_ entry: ImportedShareEntry) {
        pendingShareConfirmation = nil
        switch entry.entryType {
        case .freeTrial:
            pendingRoute = .trial(entry.id)
            pendingCancelTrialID = entry.id
        case .subscription:
            pendingRoute = .subscription(entry.id)
            pendingCancelTrialID = nil
        }
    }
}

struct ContentView: View {
    @Environment(AppRouter.self) private var appRouter
    let notificationEngine: NotificationEngine
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @Query private var existingTrials: [Trial]
    @State private var showingDemoPreview = false

    var body: some View {
        Group {
            if shouldShowOnboarding {
                OnboardingView(
                    onPreviewDemo: {
                        showingDemoPreview = true
                    },
                    onFinish: {
                        hasCompletedOnboarding = true
                    }
                )
            } else {
                RootTabView(notificationEngine: notificationEngine)
            }
        }
        .onAppear {
            // One-time migration: anyone who already has real trial data
            // (from the prior Gmail build, or who added trials before
            // tapping "Open Finn" in onboarding) shouldn't be re-onboarded.
            if !hasCompletedOnboarding && !existingTrials.isEmpty {
                hasCompletedOnboarding = true
            }
        }
        .onChange(of: appRouter.pendingSharedTrialText) { _, newValue in
            if newValue != nil {
                hasCompletedOnboarding = true
            }
        }
    }

    private var shouldShowOnboarding: Bool {
        !hasCompletedOnboarding && !showingDemoPreview
    }
}

private struct RootTabView: View {
    enum Tab {
        case home
        case trials
        case subscriptions
        case settings
    }

    @Environment(AppRouter.self) private var appRouter
    let notificationEngine: NotificationEngine
    @State private var selection: Tab = .home

    init(notificationEngine: NotificationEngine) {
        self.notificationEngine = notificationEngine
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundColor = UIColor(FinnTheme.background).withAlphaComponent(0.72)
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.shadowColor = UIColor(FinnTheme.divider).withAlphaComponent(0.8)

        let inactive = UIColor(FinnTheme.tertiaryText)
        appearance.stackedLayoutAppearance.normal.iconColor = inactive
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: inactive]

        let active = UIColor(FinnTheme.accent)
        appearance.stackedLayoutAppearance.selected.iconColor = active
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: active]

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        // SwiftUI tabItem icons must be SF Symbols — custom views render at intrinsic size and blow out the tab bar.
        // Falling back to SF Symbols for tab chrome only (FinnTheme.accent tint preserves the lavender brand).
        TabView(selection: $selection) {
            HomeView(notificationEngine: notificationEngine)
                .tabItem {
                    Label("Home", systemImage: selection == .home ? "house.fill" : "house")
                }
                .tag(Tab.home)

            SubscriptionsView()
                .tabItem {
                    Label("Subscriptions", systemImage: selection == .subscriptions ? "repeat.circle.fill" : "repeat")
                }
                .tag(Tab.subscriptions)

            TrialsView(notificationEngine: notificationEngine)
                .tabItem {
                    Label("Trials", systemImage: selection == .trials ? "clock.fill" : "clock")
                }
                .tag(Tab.trials)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: selection == .settings ? "gearshape.fill" : "gearshape")
                }
                .tag(Tab.settings)
        }
        .tint(FinnTheme.accent)
        .onChange(of: selection) { _, _ in
            Haptics.play(.tabSwitch)
        }
        .onChange(of: appRouter.pendingRoute) { _, newRoute in
            // Switch to the tab that owns the entry type so the sheet lands
            // in the right place. HomeView + SubscriptionsView each watch
            // `pendingRoute` and present their own detail sheet.
            switch newRoute {
            case .trial:
                selection = .home
            case .subscription:
                selection = .subscriptions
            case .none:
                break
            }
        }
        .overlay(alignment: .top) {
            if let confirmation = appRouter.pendingShareConfirmation {
                ShareImportToast(
                    entry: confirmation,
                    onTap: {
                        Haptics.play(.rowTap)
                        appRouter.openShareConfirmation(confirmation)
                    },
                    onDismiss: {
                        guard appRouter.pendingShareConfirmation?.id == confirmation.id else { return }
                        appRouter.pendingShareConfirmation = nil
                    }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            } else if appRouter.pendingLimitNudgeCount > 0 {
                ShareLimitToast(
                    skippedCount: appRouter.pendingLimitNudgeCount,
                    onTap: {
                        Haptics.play(.rowTap)
                        appRouter.pendingLimitNudgeCount = 0
                        appRouter.presentingLimitPaywall = true
                    },
                    onDismiss: { appRouter.pendingLimitNudgeCount = 0 }
                )
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(FinnMotion.standard, value: appRouter.pendingShareConfirmation?.id)
        .animation(FinnMotion.standard, value: appRouter.pendingLimitNudgeCount)
        .sheet(isPresented: Bindable(appRouter).presentingLimitPaywall) {
            FinnProPaywallView()
        }
    }
}

private struct ShareImportToast: View {
    let entry: ImportedShareEntry
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Ph.checkCircle.fill
                    .color(FinnTheme.accent)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(FinnTheme.primaryText)
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FinnTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Ph.caretRight.bold
                    .color(FinnTheme.tertiaryText)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FinnTheme.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FinnTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). \(detail). Tap to edit.")
        .task(id: entry.id) {
            try? await Task.sleep(for: .seconds(2))
            onDismiss()
        }
    }

    private var title: String {
        switch entry.entryType {
        case .freeTrial:
            return "Saved \(entry.serviceName) trial"
        case .subscription:
            return "Saved \(entry.serviceName) subscription"
        }
    }

    private var detail: String {
        let date = entry.chargeDate.formatted(.dateTime.month(.abbreviated).day())
        guard let amount = entry.chargeAmount else { return date }
        return "\(date) · \(formatUSD(amount))"
    }
}

/// Shown when the share extension captured more than the free tier allows.
/// Tapping opens the paywall; the conversion hook is "you already captured
/// these, upgrade to keep them."
private struct ShareLimitToast: View {
    let skippedCount: Int
    let onTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Ph.sparkle.fill
                    .color(FinnTheme.accent)
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(FinnTheme.primaryText)
                        .lineLimit(1)

                    Text("Upgrade to Finn Pro to keep them all.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FinnTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Ph.caretRight.bold
                    .color(FinnTheme.tertiaryText)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(FinnTheme.backgroundElevated)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(FinnTheme.glassBorder, lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.24), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title). Upgrade to Finn Pro to keep them all.")
        .task(id: skippedCount) {
            try? await Task.sleep(for: .seconds(4))
            onDismiss()
        }
    }

    private var title: String {
        skippedCount == 1
            ? "1 capture skipped — at your free limit"
            : "\(skippedCount) captures skipped — at your free limit"
    }
}

enum PresentingHost {
    static func rootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first(where: { $0.isKeyWindow })?.rootViewController
    }
}

func formatUSD(_ value: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "USD"
    return formatter.string(from: value as NSDecimalNumber) ?? "$\(value)"
}

func trialLengthDescription(for trial: Trial) -> String? {
    guard let days = trial.trialLengthDays else { return nil }
    if days >= 350 { return "1-year trial" }
    if days >= 80 && days <= 100 { return "3-month trial" }
    if days >= 55 && days <= 65 { return "2-month trial" }
    if days >= 28 && days <= 32 { return "1-month trial" }
    return "\(days)-day trial"
}

func daysUntil(_ date: Date, from now: Date = Date()) -> Int {
    let calendar = Calendar.current
    let d1 = calendar.startOfDay(for: now)
    let d2 = calendar.startOfDay(for: date)
    return calendar.dateComponents([.day], from: d1, to: d2).day ?? 0
}

func trialCountdownBadgeText(days: Int, includeLeft: Bool = false) -> String {
    if days < 0 { return "PAST DUE" }
    if days == 0 { return "TODAY" }
    return includeLeft ? "\(days)D LEFT" : "\(days)D"
}
