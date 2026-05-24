import NotificationEngine
import OSLog
import SubscriptionStore
import SwiftData
import SwiftUI
import TrialEngine
import UserNotifications

private let schemaLog = Logger(subsystem: "com.colehollander.finn", category: "schema")

@main
@MainActor
struct FinnApp: App {
    @Environment(\.scenePhase) private var scenePhase

    private static let modelContainer: ModelContainer = {
        let schema = Schema([
            Trial.self,
            TrialAlert.self,
        ])
        let configuration = ModelConfiguration(schema: schema)

        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            schemaLog.error("ModelContainer load failed: \(String(describing: error), privacy: .public)")

            guard isUnrecoverableSchemaError(error) else {
                schemaLog.info("Retrying ModelContainer load without wipe")
                do {
                    return try ModelContainer(for: schema, configurations: [configuration])
                } catch {
                    schemaLog.error("Retry also failed: \(String(describing: error), privacy: .public) — falling through to wipe")
                    return wipeAndReload(schema: schema, configuration: configuration)
                }
            }

            schemaLog.notice("Error classified as unrecoverable — wiping on-disk store")
            return wipeAndReload(schema: schema, configuration: configuration)
        }
    }()

    private static func wipeAndReload(schema: Schema, configuration: ModelConfiguration) -> ModelContainer {
        wipeStore()
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("ModelContainer load failed after wipe: \(error)")
        }
    }

    /// True only when the error signals a schema incompatibility that
    /// SwiftData cannot reconcile via lightweight migration. For everything
    /// else — transient filesystem hiccups, permission issues, container
    /// bootstrap problems — we retry instead of wiping the user's data.
    private static func isUnrecoverableSchemaError(_ error: Error) -> Bool {
        let nsError = error as NSError
        let desc = (nsError.userInfo[NSLocalizedDescriptionKey] as? String ?? nsError.localizedDescription).lowercased()
        let keywords = ["incompatible", "schema", "migration", "validation", "hashmodifier", "attribute"]
        return keywords.contains(where: desc.contains)
    }

    /// Retained for the lifetime of the app — UNUserNotificationCenter holds
    /// a weak reference so the delegate must outlive it.
    private let appRouter: AppRouter
    private let notificationDelegate: NotificationDelegate
    private let notificationEngine = NotificationEngine()
    private let autoImportService = AutoImportService()
    private let appEntitlements = AppEntitlements()

    init() {
        let router = AppRouter()
        self.appRouter = router

        let delegate = NotificationDelegate(
            modelContainer: Self.modelContainer,
            appRouter: router
        )
        self.notificationDelegate = delegate
        UNUserNotificationCenter.current().delegate = delegate

        let container = Self.modelContainer
        let engine = notificationEngine

        Task {
            let coordinator = TrialAlertCoordinator(
                modelContainer: container,
                notificationEngine: engine
            )
            await coordinator.replanAll()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(notificationEngine: notificationEngine)
                .modelContainer(Self.modelContainer)
                .environment(appRouter)
                .environment(autoImportService)
                .environment(appEntitlements)
                // Force the warm-charcoal window background so view transitions
                // (tab switches, sheets) don't flash white→gray before content
                // composites in. Also forces dark color scheme everywhere so
                // any system-rendered surface (sheet edges, alerts) matches.
                .background(FinnTheme.background.ignoresSafeArea())
                .preferredColorScheme(.dark)
                .task {
                    let context = Self.modelContainer.mainContext
                    let importedEntries = SharedCaptureImporter.importPendingEntries(context: context)
                    appRouter.showShareConfirmation(for: importedEntries)
                    appEntitlements.start()
                    autoImportService.startTransactionUpdates(context: context)
                    await autoImportService.sync(context: context)
                }
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active else { return }

                    Task {
                        let context = Self.modelContainer.mainContext
                        await MainActor.run {
                            let importedEntries = SharedCaptureImporter.importPendingEntries(context: context)
                            appRouter.showShareConfirmation(for: importedEntries)
                        }
                        await autoImportService.sync(context: context)
                    }
                }
                .onOpenURL { url in
                    _ = appRouter.handle(url: url)
                }
        }
    }
}

/// Wipe the on-disk SwiftData store (default.store + SQLite sidecar files).
/// Used when the schema has changed incompatibly and we want a clean slate.
private func wipeStore() {
    guard let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
        return
    }
    let candidates = [
        appSupport.appendingPathComponent("default.store"),
        appSupport.appendingPathComponent("default.store-shm"),
        appSupport.appendingPathComponent("default.store-wal"),
    ]
    for url in candidates {
        try? FileManager.default.removeItem(at: url)
    }
}
