import Foundation
import SwiftData

@main
struct AccountUpdateChecks {
    @MainActor
    static func main() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: Expense.self, AssetAccount.self, AssetBalanceSnapshot.self,
            StockHolding.self, AssetTransfer.self, AssetFXRate.self, configurations: config)
        let context = container.mainContext
        let start = Date(timeIntervalSince1970: 1000)
        let checked = start.addingTimeInterval(100)
        let updated = checked.addingTimeInterval(100)
        let latest = updated.addingTimeInterval(100)
        precondition(AssetKind.selectable.count == 4)
        precondition([AssetKind.debitCard, .passbook, .wechat, .alipayBalance, .yuebao].allSatisfy { $0.category == .funds })
        let account = AssetAccount(name: "我的工资卡", kind: .funds, lastFour: "1234", createdAt: start)
        let legacy = AssetAccount(name: "原存折", kind: .passbook, createdAt: start)
        context.insert(account); context.insert(legacy)
        context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: 10000, date: checked, note: "核对"))
        try context.save()
        var portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.lastUpdateDate(account) == checked)
        account.recordUpdate(at: updated, previousDate: portfolio.lastUpdateDate(account))
        try context.save()
        precondition(account.previousUpdatedAt == checked && account.updatedAt == updated)
        precondition(portfolio.lastUpdateDate(account) == updated)
        account.recordUpdate(at: latest)
        try context.save()
        let fetched = try context.fetch(FetchDescriptor<AssetAccount>()).first { $0.name == "我的工资卡" }!
        precondition(fetched.previousUpdatedAt == updated && fetched.updatedAt == latest)
        precondition(legacy.kind == .passbook && legacy.kind.category == .funds && legacy.name == "原存折")
        precondition(AssetRepository.matchingAccount(method: "银行(1234)", in: [account]) === account)
        let wechat = AssetAccount(name: "微信零钱", kind: .funds)
        precondition(AssetRepository.matchingAccount(method: "零钱", in: [wechat]) === wechat)
        precondition(AssetRepository.matchingAccount(method: "零钱通", in: [wechat]) == nil)
        let duplicate = AssetAccount(name: "第二张卡", kind: .funds, lastFour: "1234")
        precondition(AssetRepository.matchingAccount(method: "银行(1234)", in: [account, duplicate]) == nil)
        let yuebao = AssetAccount(name: "余额宝", kind: .funds)
        precondition(AssetRepository.matchingAccount(method: "余额", in: [yuebao]) == nil)
        let expense = Expense(amountInCents: 1000, category: "餐饮", note: "", date: latest.addingTimeInterval(1))
        expense.accountID = account.id; context.insert(expense); try context.save()
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.balance(account) == 9000 && portfolio.lastUpdateDate(account) == latest)
        print("Account types and update timestamps: 13 checks passed")
    }
}
