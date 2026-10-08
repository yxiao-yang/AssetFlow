import Foundation
import SwiftData

@main
struct AssetIntegrationChecks {
    @MainActor
    static func main() throws {
        let container = try ModelContainer(for: Expense.self, AssetAccount.self, AssetBalanceSnapshot.self,
            StockHolding.self, AssetTransfer.self, AssetFXRate.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let baseline = Date(timeIntervalSince1970: 1000)
        let later = baseline.addingTimeInterval(100)
        let bank = AssetAccount(name: "银行", kind: .debitCard, lastFour: "4132", createdAt: baseline)
        let wallet = AssetAccount(name: "零钱", kind: .wechat, createdAt: baseline)
        context.insert(bank); context.insert(wallet)
        context.insert(AssetBalanceSnapshot(accountID: bank.id, amountInCents: 10000, date: baseline, note: "期初"))
        context.insert(AssetBalanceSnapshot(accountID: wallet.id, amountInCents: 1000, date: baseline, note: "期初"))
        let expense = Expense(amountInCents: 2850, category: "餐饮", note: "消费", date: later)
        expense.accountID = bank.id; context.insert(expense)
        try context.save()
        var portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.balance(bank) == 7150)
        precondition(portfolio.total == 8150)
        expense.needsConfirmation = true
        try context.save()
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.balance(bank) == 10000)
        precondition(AssetRepository.matchingAccount(method: "招商银行(4132)", in: [bank, wallet]) === bank)
        precondition(AssetRepository.matchingAccount(method: "零钱通", in: [bank, wallet]) == nil)
        precondition(AssetRepository.matchingAccount(method: "零钱", in: [bank, wallet]) === wallet)
        let ambiguous = AssetAccount(name: "同尾号卡", kind: .debitCard, lastFour: "4132")
        precondition(AssetRepository.matchingAccount(method: "招商银行(4132)", in: [bank, ambiguous]) == nil)
        context.insert(AssetTransfer(fromID: bank.id, toID: wallet.id, amountInCents: 2000, receivedInCents: 2000, date: later.addingTimeInterval(1), note: "转账"))
        try context.save()
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.total == 11000)
        precondition(portfolio.balance(bank) == 8000 && portfolio.balance(wallet) == 3000)
        let brokerage = AssetAccount(name: "股票账户", kind: .stocks, createdAt: baseline)
        brokerage.currencyCode = "CNY"; context.insert(brokerage)
        let stock = StockHolding(accountID: brokerage.id, name: "示例股", symbol: "00001", quantityText: "1000", costPriceText: "36.20", priceText: "39.50")
        context.insert(stock)
        context.insert(AssetBalanceSnapshot(accountID: brokerage.id, amountInCents: 4000000, date: baseline, note: "证券估值"))
        try context.save()
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.total == 4011000)
        precondition(portfolio.stockCash(brokerage) == 50000)
        precondition(stock.profit == 330000)
        // Old exchange-rate records no longer affect the CNY-only total.
        context.insert(AssetFXRate(rateText: "0.9", date: baseline))
        try context.save()
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.total == 4011000)
        context.delete(expense)
        try context.save()
        let count = try context.fetchCount(FetchDescriptor<AssetAccount>())
        precondition(count == 3)
        print("Asset persistence: 14 checks passed")
    }
}
