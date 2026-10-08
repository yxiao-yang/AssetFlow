import Foundation

@main
struct AnalyticsChecks {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        func date(_ month: Int, _ day: Int) -> Date {
            cal.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
        }
        let rows = [
            LedgerRecord(amountInCents: 2850, category: "餐饮", date: date(10, 1), isIncome: false, needsConfirmation: false),
            LedgerRecord(amountInCents: 500, category: "交通", date: date(10, 1), isIncome: false, needsConfirmation: false),
            LedgerRecord(amountInCents: 100000, category: "工资", date: date(10, 2), isIncome: true, needsConfirmation: false),
            LedgerRecord(amountInCents: 9000, category: "购物", date: date(10, 3), isIncome: false, needsConfirmation: true),
            LedgerRecord(amountInCents: 8888, category: "餐饮", date: date(9, 30), isIncome: false, needsConfirmation: false)
        ]
        let stats = LedgerAnalytics(records: rows, month: date(10, 8), calendar: cal)
        precondition(stats.expense == 3350)
        precondition(stats.income == 100000)
        precondition(stats.balance == 96650)
        precondition(stats.monthlyRecords.count == 3)
        precondition(stats.categories(isIncome: false).map(\.category) == ["餐饮", "交通"])
        precondition(stats.categories(isIncome: true).first?.category == "工资")
        precondition(stats.days.count == 31)
        precondition(stats.days[0].expense == 3350 && stats.days[0].count == 2)
        precondition(stats.days[1].income == 100000)
        precondition(stats.days[2].count == 0)
        precondition(LedgerAnalytics(records: [], month: date(2, 1), calendar: cal).days.count == 28)
        precondition(LedgerAnalytics(records: [], month: date(2, 1), calendar: cal).balance == 0)
        print("Ledger analytics: 12 checks passed")
    }
}
