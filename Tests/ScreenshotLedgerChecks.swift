import Foundation
import SwiftData

@main
struct ScreenshotLedgerChecks {
    @MainActor
    static func main() throws {
        let container = try ModelContainer(for: Expense.self, AssetAccount.self, AssetBalanceSnapshot.self,
            StockHolding.self, AssetTransfer.self, AssetFXRate.self, TermDeposit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let account = AssetAccount(name: "我的余额宝", kind: .funds, createdAt: Date(timeIntervalSince1970: 1_000))
        context.insert(account)
        context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: 10000, date: account.createdAt, note: "期初"))
        try context.save()
        let data = Data("same original screenshot".utf8)
        let failed = PaymentParser.parse("交易成功", now: now)
        guard case .saved(let pending) = try ScreenshotLedgerService.save(failed, screenshotData: data, in: context, now: now) else { preconditionFailure() }
        precondition(pending.needsConfirmation && !pending.isIncome)
        let initialTotal = try AssetRepository.fetch(context).total
        precondition(initialTotal == 10000)
        let yield = PaymentParser.parse("余额宝\n0.16\n交易成功\n创建时间 2026-10-08 03:05:12\n余额宝-收益发放", now: now)
        guard case .saved(let repaired) = try ScreenshotLedgerService.save(yield, screenshotData: data, in: context, existingRecord: pending, now: now) else { preconditionFailure() }
        precondition(repaired === pending && repaired.isIncome && repaired.amountInCents == 16)
        precondition(repaired.category == "理财收益" && !repaired.needsConfirmation && repaired.accountID == account.id)
        let count = try context.fetchCount(FetchDescriptor<Expense>())
        precondition(count == 1)
        let total0 = try AssetRepository.fetch(context).total
        precondition(total0 == 10016)
        guard case .duplicate = try ScreenshotLedgerService.save(yield, screenshotData: data, in: context, now: now) else { preconditionFailure() }
        let total1 = try AssetRepository.fetch(context).total
        precondition(total1 == 10016)
        let duplicateData = Data("different image same transaction".utf8)
        guard case .saved(let possibleDuplicate) = try ScreenshotLedgerService.save(yield, screenshotData: duplicateData, in: context, now: now) else { preconditionFailure() }
        precondition(possibleDuplicate.needsConfirmation)
        let total2 = try AssetRepository.fetch(context).total
        precondition(total2 == 10016)
        let expense = PaymentParser.parse("账单详情\n示例商店\n-4.20\n交易成功\n支付时间 2026-10-08 10:00:00\n付款方式 我的余额宝\n商品说明 一份早餐", now: now)
        guard case .saved(let purchase) = try ScreenshotLedgerService.save(expense, screenshotData: Data("purchase".utf8), in: context, now: now) else { preconditionFailure() }
        precondition(!purchase.isIncome && purchase.amountInCents == 420 && purchase.note == "一份早餐")
        let absent = Expense(amountInCents: 1, category: "其他", note: "", date: now)
        do {
            _ = try ScreenshotLedgerService.save(yield, screenshotData: data, in: context, existingRecord: absent, now: now)
            preconditionFailure("Missing record accepted")
        } catch ScreenshotRecordError.missing {}
        print("Screenshot ledger persistence and retry checks passed")
    }
}
