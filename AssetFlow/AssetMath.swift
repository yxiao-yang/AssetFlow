import Foundation

enum AssetMath {
    static func cents(_ text: String, allowZero: Bool = true) -> Int? {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.range(of: #"^[0-9]+(?:\.[0-9]{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX")),
              value >= 0, value <= 999_999_999, allowZero || value > 0 else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }
    static func exchangeRate(_ text: String) -> Decimal? {
        guard text.range(of: #"^[0-9]+(?:\.[0-9]{1,8})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value > 0, value < 10 else { return nil }
        return value
    }
    static func convert(_ cents: Int, rate: Decimal) -> Int {
        var value = Decimal(cents) * rate
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
    static func quantity(_ text: String) -> Decimal? {
        guard text.range(of: #"^[0-9]+(?:\.[0-9]{1,6})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              value > 0, value <= 100_000_000 else { return nil }
        return value
    }
    static func stockPrice(_ text: String) -> Decimal? {
        guard text.range(of: #"^[0-9]+(?:\.[0-9]{1,4})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")), value >= 0, value <= 999_999 else { return nil }
        return value
    }
    static func positionValue(_ quantityText: String, priceText: String) -> Int? {
        guard let quantity = quantity(quantityText), let price = stockPrice(priceText) else { return nil }
        var raw = quantity * price * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &raw, 0, .plain)
        guard rounded <= Decimal(99_999_999_999) else { return nil }
        return NSDecimalNumber(decimal: rounded).intValue
    }
}

struct AssetCheckpoint {
    let accountID: UUID
    let cents: Int
    let date: Date
}
struct AssetMovement {
    let accountID: UUID
    let cents: Int
    let date: Date
}
struct AssetHistoryPoint: Identifiable {
    var id: Date { date }
    let date: Date
    let cents: Int
}

struct AssetBalanceEngine {
    let checkpoints: [AssetCheckpoint]
    let movements: [AssetMovement]
    func value(accountID: UUID, at date: Date) -> Int? {
        guard let baseline = checkpoints.filter({ $0.accountID == accountID && $0.date <= date })
            .max(by: { $0.date < $1.date }) else { return nil }
        return baseline.cents + movements.filter {
            $0.accountID == accountID && $0.date > baseline.date && $0.date <= date
        }.reduce(0) { $0 + $1.cents }
    }
    func total(accountIDs: [UUID], at date: Date) -> Int {
        accountIDs.reduce(0) { $0 + (value(accountID: $1, at: date) ?? 0) }
    }
    func history(accountIDs: [UUID], since start: Date, until end: Date, calendar: Calendar = .current) -> [AssetHistoryPoint] {
        guard start <= end else { return [] }
        var points: [AssetHistoryPoint] = []
        var day = calendar.startOfDay(for: start)
        while day < end {
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            let sample = min(next.addingTimeInterval(-0.001), end)
            points.append(AssetHistoryPoint(date: sample, cents: total(accountIDs: accountIDs, at: sample)))
            day = next
        }
        if points.last?.date != end {
            points.append(AssetHistoryPoint(date: end, cents: total(accountIDs: accountIDs, at: end)))
        }
        return points
    }
}
