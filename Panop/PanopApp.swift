import Foundation
import SwiftData
import SwiftUI

@main
struct PanopApp: App {
    private let catalogContainer: ModelContainer
    private let cloudContainer: ModelContainer
    private let services: AppServices

    init() {
        // A hosted test run launches this app first. It must not open, or worse
        // migrate, the developer's real stores.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || UITestMode.isActive
        do {
            let catalog = try PanopContainers.makeCatalog(inMemory: underTest)
            let cloud = try PanopContainers.makeCloud(inMemory: underTest)
            catalogContainer = catalog
            cloudContainer = cloud
            services = AppServices(
                catalog: catalog,
                cloud: cloud,
                // Tests and previews must never write to the developer's real Keychain.
                credentials: underTest ? InMemoryCredentialStore() : KeychainCredentialStore()
            )
            #if DEBUG
                if UITestMode.isActive {
                    UITestMode.resetPreferences()
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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(\.cloudModelContext, ModelContext(cloudContainer))
                .environment(services.library)
                .environment(services.userState)
                .environment(services.syncStatus)
        }
        .modelContainer(catalogContainer)
    }
}

extension EnvironmentValues {
    @Entry var cloudModelContext: ModelContext?
}
