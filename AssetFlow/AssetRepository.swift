import Foundation
import SwiftData

struct AssetPortfolio {
    let accounts: [AssetAccount]
    let snapshots: [AssetBalanceSnapshot]
    let holdings: [StockHolding]
    let transfers: [AssetTransfer]
    let expenses: [Expense]
    let rates: [AssetFXRate]

    var activeAccounts: [AssetAccount] { accounts.filter { $0.archivedAt == nil } }
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
    func rate(at date: Date = .now) -> Decimal? {
        rates.filter { $0.date <= date }.max(by: { $0.date < $1.date }).flatMap { AssetMath.exchangeRate($0.rateText) }
    }
    func converted(_ account: AssetAccount, at date: Date = .now) -> Int? {
        let value = balance(account, at: date)
        if account.currencyCode == "CNY" { return value }
        guard let rate = rate(at: date) else { return nil }
        return AssetMath.convert(value, rate: rate)
    }
    var total: Int? {
        let values = activeAccounts.map { converted($0) }
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return values.reduce(0) { $0 + ($1 ?? 0) }
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
            let relevant = accounts.filter { $0.createdAt <= date && ($0.archivedAt == nil || $0.archivedAt! > date) }
            let values = relevant.map { converted($0, at: date) }
            guard values.allSatisfy({ $0 != nil }) else { return nil }
            return AssetHistoryPoint(date: date, cents: values.reduce(0) { $0 + ($1 ?? 0) })
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
            expenses: try context.fetch(FetchDescriptor<Expense>()),
            rates: try context.fetch(FetchDescriptor<AssetFXRate>()))
    }
    static func matchingAccount(method: String?, in accounts: [AssetAccount]) -> AssetAccount? {
        guard let method, !method.isEmpty else { return nil }
        let matches = accounts.filter { account in
            guard account.archivedAt == nil, account.currencyCode == "CNY" else { return false }
            switch account.kind {
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
