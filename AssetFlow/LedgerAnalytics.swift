import Foundation

struct LedgerRecord {
    let amountInCents: Int
    let category: String
    let date: Date
    let isIncome: Bool
    let needsConfirmation: Bool
}

struct CategoryTotal: Identifiable {
    var id: String { category }
    let category: String
    let cents: Int
    let count: Int
}

struct DailyTotal: Identifiable {
    var id: Date { date }
    let date: Date
    let expense: Int
    let income: Int
    let count: Int
}

struct LedgerAnalytics {
    let records: [LedgerRecord]
    let month: Date
    var calendar = Calendar.current

    var monthlyRecords: [LedgerRecord] {
        records.filter { !$0.needsConfirmation && calendar.isDate($0.date, equalTo: month, toGranularity: .month) }
    }
    var expense: Int { monthlyRecords.filter { !$0.isIncome }.reduce(0) { $0 + $1.amountInCents } }
    var income: Int { monthlyRecords.filter(\.isIncome).reduce(0) { $0 + $1.amountInCents } }
    var balance: Int { income - expense }

    func categories(isIncome: Bool) -> [CategoryTotal] {
        Dictionary(grouping: monthlyRecords.filter { $0.isIncome == isIncome }, by: \.category).map { category, rows in
            CategoryTotal(category: category, cents: rows.reduce(0) { $0 + $1.amountInCents }, count: rows.count)
        }.sorted { $0.cents == $1.cents ? $0.category < $1.category : $0.cents > $1.cents }
    }

    var days: [DailyTotal] {
        guard let interval = calendar.dateInterval(of: .month, for: month),
              let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let grouped = Dictionary(grouping: monthlyRecords) { calendar.startOfDay(for: $0.date) }
        return range.compactMap { day in
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: interval.start) else { return nil }
            let rows = grouped[date] ?? []
            return DailyTotal(date: date,
                expense: rows.filter { !$0.isIncome }.reduce(0) { $0 + $1.amountInCents },
                income: rows.filter(\.isIncome).reduce(0) { $0 + $1.amountInCents }, count: rows.count)
        }
    }
}
