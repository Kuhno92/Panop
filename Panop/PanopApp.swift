import Foundation
import SwiftData
import SwiftUI

@main
struct PanopApp: App {
    private let catalogContainer: ModelContainer
    private let cloudContainer: ModelContainer

    init() {
        // A hosted test run launches this app first. It must not open, or worse
        // migrate, the developer's real stores.
        let underTest = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        do {
            catalogContainer = try PanopContainers.makeCatalog(inMemory: underTest)
            cloudContainer = try PanopContainers.makeCloud(inMemory: underTest)
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
        }
        .modelContainer(catalogContainer)
    }
}

extension EnvironmentValues {
    @Entry var cloudModelContext: ModelContext?
}
