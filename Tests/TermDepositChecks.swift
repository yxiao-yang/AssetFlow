import Foundation
import SwiftData

@main
struct TermDepositChecks {
    @MainActor static func main() throws {
        let container = try ModelContainer(for: Expense.self, AssetAccount.self, AssetBalanceSnapshot.self,
            StockHolding.self, AssetTransfer.self, AssetFXRate.self, TermDeposit.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let firstDay = calendar.startOfDay(for: now)
        let nextYear = calendar.date(byAdding: .day, value: 365, to: firstDay)!
        precondition(TermDepositMath.estimatedInterest(principal: 2_000_000, rate: "1.5", start: firstDay, end: nextYear, calendar: calendar) == 30000)
        precondition(TermDepositMath.estimatedInterest(principal: 100, rate: "1", start: firstDay, end: firstDay, calendar: calendar) == nil)
        precondition(TermDepositMath.rate("100.0001") == nil)
        let account = AssetAccount(name: "同一本存折", kind: .funds, createdAt: now.addingTimeInterval(-100))
        account.managesTermDeposits = true
        let bank = AssetAccount(name: "另一张卡", kind: .funds, createdAt: now.addingTimeInterval(-100))
        context.insert(account); context.insert(bank)
        context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: 5_000_000, date: account.createdAt, note: "含定期总余额"))
        context.insert(AssetBalanceSnapshot(accountID: bank.id, amountInCents: 100_000, date: bank.createdAt, note: "期初"))
        try context.save()
        try TermDepositRepository.save(account: account, name: "第一笔", principal: 2_000_000, rate: "1.5", openedAt: firstDay, maturity: nextYear, note: "", context: context, now: now)
        try TermDepositRepository.save(account: account, name: "第二笔", principal: 2_500_000, rate: "2", openedAt: firstDay, maturity: nextYear, note: "", context: context, now: now.addingTimeInterval(1))
        var portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.termPrincipal(account) == 4_500_000)
        precondition(portfolio.availableBalance(account) == 500_000)
        precondition(portfolio.total == 5_100_000 && portfolio.expenses.isEmpty)
        precondition(portfolio.termDeposits(account).count == 2)
        let first = portfolio.deposits.first { $0.name == "第一笔" }!
        precondition(first.status(at: nextYear) == "已到期 · 未取出" && first.isOutstanding)
        do {
            try TermDepositRepository.save(account: account, name: "超额", principal: 500_001, rate: "1", openedAt: firstDay, maturity: nextYear, note: "", context: context, now: now.addingTimeInterval(2))
            preconditionFailure("Over-allocation accepted")
        } catch TermDepositError.insufficient {}
        let countAfterFailure = try context.fetchCount(FetchDescriptor<TermDeposit>())
        precondition(countAfterFailure == 2)
        try TermDepositRepository.save(account: account, existing: first, name: "第一笔", principal: 1_900_000, rate: "1.5", openedAt: firstDay, maturity: nextYear, note: "修改", context: context, now: now.addingTimeInterval(3))
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.availableBalance(account) == 600_000 && portfolio.total == 5_100_000)
        try TermDepositRepository.withdraw(first, to: bank, interest: 30000, context: context, now: now.addingTimeInterval(4))
        portfolio = try AssetRepository.fetch(context)
        precondition(first.status() == "已取出" && first.settledInterestInCents == 30000)
        precondition(portfolio.balance(account) == 3_100_000 && portfolio.balance(bank) == 2_030_000)
        precondition(portfolio.termPrincipal(account) == 2_500_000 && portfolio.availableBalance(account) == 600_000)
        precondition(portfolio.total == 5_130_000)
        precondition(portfolio.transfers.count == 1 && portfolio.transfers[0].amountInCents == 1_900_000)
        precondition(portfolio.expenses.count == 1 && portfolio.expenses[0].isIncome && portfolio.expenses[0].amountInCents == 30000)
        do {
            try TermDepositRepository.withdraw(first, to: bank, interest: 30000, context: context, now: now.addingTimeInterval(5))
            preconditionFailure("Duplicate withdrawal accepted")
        } catch TermDepositError.closed {}
        let second = portfolio.deposits.first { $0.name == "第二笔" }!
        try TermDepositRepository.renew(second, principal: 2_550_000, rate: "1.6", maturity: nextYear, interest: 50000, context: context, now: now.addingTimeInterval(6))
        portfolio = try AssetRepository.fetch(context)
        let renewed = portfolio.deposits.first { $0.originDepositID == second.id }!
        precondition(second.status() == "已转存" && !second.isOutstanding && renewed.isOutstanding)
        precondition(portfolio.termPrincipal(account) == 2_550_000 && portfolio.availableBalance(account) == 600_000)
        precondition(portfolio.total == 5_180_000 && portfolio.expenses.count == 2)
        try TermDepositRepository.withdraw(renewed, to: account, interest: 0, context: context, now: now.addingTimeInterval(7))
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.termPrincipal(account) == 0 && portfolio.availableBalance(account) == 3_150_000)
        precondition(portfolio.total == 5_180_000 && portfolio.expenses.count == 2 && portfolio.transfers.count == 1)
        try TermDepositRepository.save(account: account, name: "误录", principal: 1000, rate: "0", openedAt: firstDay, maturity: nextYear, note: "", context: context, now: now.addingTimeInterval(8))
        let mistaken = try AssetRepository.fetch(context).deposits.first { $0.name == "误录" }!
        try TermDepositRepository.removeRecord(mistaken, context: context, now: now.addingTimeInterval(9))
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.total == 5_180_000 && portfolio.termPrincipal(account) == 0)
        try AssetRepository.deleteAccount(account, in: context)
        portfolio = try AssetRepository.fetch(context)
        precondition(portfolio.deposits.isEmpty && portfolio.accounts.count == 1 && portfolio.balance(bank) == 2_030_000)
        precondition(portfolio.expenses.count == 2 && portfolio.transfers.count == 1)
        print("Term deposits: all checks passed")
    }
}
