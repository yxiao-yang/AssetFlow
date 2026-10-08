import SwiftUI
import SwiftData

@main
struct MyAssetsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: Expense.self)
    }
}
