import Foundation

@main
struct AssetHistoryRangeChecks {
    @MainActor
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 12))!
        let old = calendar.date(byAdding: .day, value: -500, to: now)!
        let bank = AssetAccount(name: "储蓄", kind: .funds, createdAt: old)
        let foreign = AssetAccount(name: "旧外币", kind: .funds, createdAt: old)
        foreign.currencyCode = "HKD"
        let snapshots = [AssetBalanceSnapshot(accountID: bank.id, amountInCents: 10000, date: old, note: "期初"),
                         AssetBalanceSnapshot(accountID: foreign.id, amountInCents: 90000, date: old, note: "旧数据")]
        let spending = Expense(amountInCents: 2000, category: "餐饮", note: "", date: now.addingTimeInterval(-3600))
        spending.accountID = bank.id
        let portfolio = AssetPortfolio(accounts: [bank, foreign], snapshots: snapshots, holdings: [], transfers: [], expenses: [spending])
        for (range, count) in [(AssetHistoryRange.week, 7), (.month, 30), (.quarter, 90), (.year, 365)] {
            let points = portfolio.history(in: range, until: now, calendar: calendar)
            precondition(points.count == count)
            precondition(points.first!.date >= range.startDate(until: now, calendar: calendar)!)
            precondition(points.last!.date == now && points.last!.cents == 8000)
            precondition(points.dropLast().allSatisfy { $0.cents == 10000 })
        }
        let all = portfolio.history(in: .all, until: now, calendar: calendar)
        precondition(all.count == 501 && all.first!.date >= old && all.last!.cents == 8000)
        let recent = now.addingTimeInterval(-3600)
        let newBank = AssetAccount(name: "新账户", kind: .funds, createdAt: recent)
        let newPortfolio = AssetPortfolio(accounts: [newBank], snapshots: [AssetBalanceSnapshot(accountID: newBank.id, amountInCents: 5000, date: recent, note: "")], holdings: [], transfers: [], expenses: [])
        precondition(newPortfolio.history(in: .all, until: now, calendar: calendar).count == 1)
        let empty = AssetPortfolio(accounts: [], snapshots: [], holdings: [], transfers: [], expenses: [])
        precondition(empty.history(in: .all, until: now, calendar: calendar).isEmpty)
        precondition(portfolio.history(in: .week, until: old.addingTimeInterval(-1), calendar: calendar).isEmpty)
        print("Asset history ranges: 20 checks passed")
    }
}
