import Foundation
import SwiftData

@main
struct CNYAccountDeletionChecks {
    @MainActor
    static func main() throws {
        let container = try ModelContainer(for: Expense.self, AssetAccount.self, AssetBalanceSnapshot.self,
            StockHolding.self, AssetTransfer.self, AssetFXRate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1000)
        let bank = AssetAccount(name: "我的银行卡", kind: .funds, createdAt: start)
        let peer = AssetAccount(name: "另一个账户", kind: .funds, createdAt: start)
        let foreign = AssetAccount(name: "旧外币账户", kind: .stocks, createdAt: start)
        foreign.currencyCode = "HKD"
        for account in [bank, peer, foreign] { context.insert(account) }
        context.insert(AssetBalanceSnapshot(accountID: bank.id, amountInCents: 10000, date: start, note: "期初"))
        context.insert(AssetBalanceSnapshot(accountID: peer.id, amountInCents: 1000, date: start, note: "期初"))
        context.insert(AssetBalanceSnapshot(accountID: foreign.id, amountInCents: 999999, date: start, note: "旧记录"))
        context.insert(AssetFXRate(rateText: "0.9", date: start))
        let expense = Expense(amountInCents: 500, category: "餐饮", note: "保留账本", date: start.addingTimeInterval(10))
        expense.accountID = bank.id; context.insert(expense)
        let pending = Expense(amountInCents: 500, category: "其他", note: "待确认", date: start.addingTimeInterval(11))
        pending.accountID = bank.id; pending.needsConfirmation = true; context.insert(pending)
        context.insert(StockHolding(accountID: bank.id, name: "用于清理的旧持仓", symbol: "00001", quantityText: "1", costPriceText: "1", priceText: "1"))
        context.insert(AssetTransfer(fromID: bank.id, toID: peer.id, amountInCents: 2000, receivedInCents: 2000, date: start.addingTimeInterval(20), note: "自己的账户转账"))
        try context.save()
        var portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.activeAccounts.count == 2)
        precondition(portfolio.total == 10500)
        precondition(portfolio.history.allSatisfy { $0.cents <= 11000 })
        precondition(AssetRepository.matchingAccount(method: "银行(1234)", in: [foreign]) == nil)
        let peerBalance = portfolio.balance(peer)
        let oldHistoricalPeerBalance = portfolio.balance(peer, at: start.addingTimeInterval(30))
        try AssetRepository.deleteAccount(bank, in: context)
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.accounts.count == 2 && portfolio.activeAccounts.count == 1)
        precondition(portfolio.expenses.count == 2 && portfolio.expenses.allSatisfy { $0.accountID == nil })
        precondition(portfolio.expenses.first { $0.note == "保留账本" }?.amountInCents == 500)
        precondition(portfolio.expenses.first { $0.note == "待确认" }?.needsConfirmation == true)
        precondition(!portfolio.snapshots.contains { $0.accountID == bank.id })
        precondition(!portfolio.holdings.contains { $0.accountID == bank.id })
        precondition(portfolio.transfers.count == 1)
        precondition(portfolio.balance(peer) == peerBalance && peerBalance == 3000)
        precondition(portfolio.balance(peer, at: start.addingTimeInterval(30)) == oldHistoricalPeerBalance)
        precondition(portfolio.total == 3000)
        precondition(portfolio.accounts.contains { $0.id == foreign.id && $0.currencyCode == "HKD" })
        print("CNY-only assets and account deletion: 15 checks passed")
    }
}
