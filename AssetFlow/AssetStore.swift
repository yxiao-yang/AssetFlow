import Foundation
import SwiftData

@MainActor
enum AssetStore {
    static let container: ModelContainer = {
        do {
            #if DEBUG
            if CommandLine.arguments.contains("--demo-ledger") {
                let container = try ModelContainer(for: Expense.self, AssetAccount.self, AssetBalanceSnapshot.self, StockHolding.self, AssetTransfer.self, AssetFXRate.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                LedgerDemo.seed(container.mainContext)
                AssetDemo.seed(container.mainContext)
                return container
            }
            #endif
            return try ModelContainer(for: Expense.self, AssetAccount.self, AssetBalanceSnapshot.self, StockHolding.self, AssetTransfer.self, AssetFXRate.self)
        }
        catch { fatalError("无法打开本地账本：\(error.localizedDescription)") }
    }()
}

