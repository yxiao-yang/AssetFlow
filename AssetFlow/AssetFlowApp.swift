import SwiftUI
import SwiftData

@main
struct AssetFlowApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(AssetStore.container)
    }
}
