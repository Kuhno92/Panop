import SwiftData
import SwiftUI

@main
struct PanopApp: App {
    private let catalogContainer: ModelContainer
    private let cloudContainer: ModelContainer

    init() {
        do {
            catalogContainer = try PanopContainers.makeCatalog()
            cloudContainer = try PanopContainers.makeCloud()
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
