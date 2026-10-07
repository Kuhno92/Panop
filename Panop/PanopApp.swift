import Foundation
import SwiftData
import SwiftUI

@main
struct PanopApp: App {
    private let catalogContainer: ModelContainer
    private let cloudContainer: ModelContainer
    private let cloudSync: CloudSyncStatus
    private let services: AppServices
    private let metricsStore: PlaybackMetricsStore?

    init() {
        // A hosted test run launches this app first. It must not open, or worse
        // migrate, the developer's real stores.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || UITestMode.isActive
        do {
            let catalog = try PanopContainers.makeCatalog(inMemory: underTest)
            // Mirrored to the person's iCloud only when it is switched on, this build may, and an account is
            // signed in; a store that will not open that way is opened locally instead.
            let opened = try PanopContainers.openCloud(
                inMemory: underTest,
                availability: CloudSync.current(underTest: underTest)
            )
            let cloud = opened.container
            let status = CloudSyncStatus(opened.availability)
            cloudSync = status
            // The account is not known at once everywhere (an Apple TV): CloudKit is asked a moment after launch, and
            // Settings says so if there is none.
            if opened.availability == .active {
                Task {
                    if await !CloudSync.accountIsAvailable() {
                        status.update(.noAccount)
                    }
                }
            }
            catalogContainer = catalog
            cloudContainer = cloud
            // The real file only for the real app: a test run must not write to it.
            metricsStore = if UITestMode.isActive {
                // A file of its own, so a UI test can see a session it just played.
                PlaybackMetricsStore(
                    file: FileManager.default.temporaryDirectory
                        .appendingPathComponent("uitest-\(UUID().uuidString).json")
                )
            } else {
                underTest ? nil : PlaybackMetricsStore()
            }
            services = AppServices(
                catalog: catalog,
                cloud: cloud,
                // Tests and previews must never write to the developer's real Keychain.
                credentials: underTest ? InMemoryCredentialStore() : KeychainCredentialStore()
            )
            #if DEBUG
                if UITestMode.isActive {
                    UITestMode.resetPreferences()
                    UITestMode.disableAnimations()
                    let seeded = services
                    Task { await UITestMode.seed(seeded) }
                }
            #endif
        } catch {
            // A container that cannot open means the store is unusable. There
            // is no sensible degraded mode, and continuing would only fail
            // later with a less useful message.
            fatalError("Could not open a SwiftData container: \(error)")
        }
    }

    #if os(macOS)
        @State private var embeddedPlayback = EmbeddedPlayback()
    #endif

    /// The app, and on a Mac a stream playing under it in the same window.
    @ViewBuilder
    private var mainWindow: some View {
        #if os(macOS)
            MainWindow { RootView() }
        #else
            RootView()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            mainWindow
                .environment(\.cloudModelContext, ModelContext(cloudContainer))
                .environment(services.library)
                .environment(services.userState)
                .environment(services.syncStatus)
                .environment(cloudSync)
                .environment(\.playbackMetrics, metricsStore)
            #if os(macOS)
                .environment(embeddedPlayback)
            #endif
        }
        .modelContainer(catalogContainer)

        #if os(macOS)
            // The player, in a window of its own. A new window does not inherit the main
            // scene's container or environment, so both are declared again here.
            WindowGroup("Player", id: PlayerWindow.id, for: PlayerWindowRequest.self) { $request in
                if let request {
                    PlayerWindowContent(request: request)
                        .environment(\.cloudModelContext, ModelContext(cloudContainer))
                        .environment(services.library)
                        .environment(services.userState)
                        .environment(services.syncStatus)
                        .environment(\.playbackMetrics, metricsStore)
                }
            }
            .modelContainer(catalogContainer)
            .defaultSize(width: 1100, height: 680)
            // A restored window would start playing a stream the moment the app opened.
            .restorationBehavior(.disabled)
            .commandsRemoved()
        #endif
    }
}

extension EnvironmentValues {
    /// Where finished viewing sessions are recorded. Nil in tests and previews, which must not
    /// write to the real file.
    @Entry var playbackMetrics: PlaybackMetricsStore?
    @Entry var cloudModelContext: ModelContext?
}
