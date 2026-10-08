import Foundation
import SwiftData

struct AssetPortfolio {
    let accounts: [AssetAccount]
    let snapshots: [AssetBalanceSnapshot]
    let holdings: [StockHolding]
    let transfers: [AssetTransfer]
    let expenses: [Expense]

    var activeAccounts: [AssetAccount] { accounts.filter { $0.archivedAt == nil && $0.currencyCode == "CNY" } }
    var engine: AssetBalanceEngine {
        let flow = expenses.filter { !$0.needsConfirmation && $0.accountID != nil }.map {
            AssetMovement(accountID: $0.accountID!, cents: $0.isIncome ? $0.amountInCents : -$0.amountInCents, date: $0.date)
        } + transfers.flatMap {
            [AssetMovement(accountID: $0.fromID, cents: -$0.amountInCents, date: $0.date),
             AssetMovement(accountID: $0.toID, cents: $0.receivedInCents, date: $0.date)]
        }
        return AssetBalanceEngine(checkpoints: snapshots.map {
            AssetCheckpoint(accountID: $0.accountID, cents: $0.amountInCents, date: $0.date)
        }, movements: flow)
    }
    func balance(_ account: AssetAccount, at date: Date = .now) -> Int {
        engine.value(accountID: account.id, at: date) ?? 0
    }
    var total: Int { activeAccounts.reduce(0) { $0 + balance($1) } }
    func lastUpdateDate(_ account: AssetAccount) -> Date {
        max(account.updatedAt ?? account.createdAt,
            snapshots.filter { $0.accountID == account.id }.map(\.date).max() ?? account.createdAt)
    }
    func positions(_ account: AssetAccount) -> [StockHolding] { holdings.filter { $0.accountID == account.id } }
    func stockValue(_ account: AssetAccount) -> Int { positions(account).reduce(0) { $0 + $1.marketValue } }
    func stockCash(_ account: AssetAccount) -> Int { balance(account) - stockValue(account) }
    var history: [AssetHistoryPoint] {
        let now = Date()
        let earliest = snapshots.map(\.date).min() ?? now
        let start = max(earliest, Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now)
        let dates = engine.history(accountIDs: accounts.map(\.id), since: start, until: now).map(\.date)
        return dates.compactMap { date in
            let relevant = accounts.filter { $0.currencyCode == "CNY" && $0.createdAt <= date && ($0.archivedAt == nil || $0.archivedAt! > date) }
            return AssetHistoryPoint(date: date, cents: relevant.reduce(0) { $0 + balance($1, at: date) })
        }
    }

}

@MainActor
enum AssetRepository {
    static func fetch(_ context: ModelContext) throws -> AssetPortfolio {
        AssetPortfolio(accounts: try context.fetch(FetchDescriptor<AssetAccount>()),
            snapshots: try context.fetch(FetchDescriptor<AssetBalanceSnapshot>()),
            holdings: try context.fetch(FetchDescriptor<StockHolding>()),
            transfers: try context.fetch(FetchDescriptor<AssetTransfer>()),
            expenses: try context.fetch(FetchDescriptor<Expense>()))
    }
    static func deleteAccount(_ account: AssetAccount, in context: ModelContext) throws {
        do {
            let portfolio = try fetch(context)
            for expense in portfolio.expenses where expense.accountID == account.id { expense.accountID = nil }
            for snapshot in portfolio.snapshots where snapshot.accountID == account.id { context.delete(snapshot) }
            for holding in portfolio.holdings where holding.accountID == account.id { context.delete(holding) }
            // Retain transfers: removing them would change balances and history in the surviving accounts.
            context.delete(account)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }
    static func matchingAccount(method: String?, in accounts: [AssetAccount]) -> AssetAccount? {
        guard let method, !method.isEmpty else { return nil }
        let matches = accounts.filter { account in
            guard account.archivedAt == nil, account.currencyCode == "CNY" else { return false }
            switch account.kind {
            case .funds:
                if account.lastFour.count == 4,
                   method.range(of: "(?<![0-9])" + account.lastFour + "(?![0-9])", options: .regularExpression) != nil { return true }
                let payment = method.trimmingCharacters(in: .whitespacesAndNewlines)
                // Generic accounts match explicit payment names; ambiguous matches remain unlinked.
                if payment.contains("零钱通") { return account.name.contains("零钱通") }
                if payment.contains("零钱") { return account.name.contains("零钱") && !account.name.contains("零钱通") }
                if payment.contains("余额宝") { return account.name.contains("余额宝") }
                if ["余额", "支付宝余额"].contains(payment) {
                    return account.name.contains("支付宝余额") && !account.name.contains("余额宝")
                }
                return false
            case .debitCard, .passbook:
                guard account.lastFour.count == 4 else { return false }
                let pattern = "(?<![0-9])" + account.lastFour + "(?![0-9])"
                return method.range(of: pattern, options: .regularExpression) != nil
            case .wechat: return method.contains("零钱") && !method.contains("零钱通")
            case .yuebao: return method.contains("余额宝")
            case .alipayBalance: return ["余额", "支付宝余额"].contains(method.trimmingCharacters(in: .whitespacesAndNewlines))
            default: return false
            }
        }
        return matches.count == 1 ? matches.first : nil
    }
}
