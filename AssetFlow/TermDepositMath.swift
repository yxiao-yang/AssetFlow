import Foundation

enum TermDepositMath {
    static func rate(_ text: String) -> Decimal? {
        guard let rate = AssetMath.stockPrice(text), rate <= 100 else { return nil }
        return rate
    }
    static func days(start: Date, end: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: start), to: calendar.startOfDay(for: end)).day ?? 0
    }
    static func estimatedInterest(principal: Int, rate text: String, start: Date, end: Date,
                                  calendar: Calendar = .current) -> Int? {
        let dayCount = days(start: start, end: end, calendar: calendar)
        guard principal > 0, let rate = rate(text), dayCount > 0 else { return nil }
        var value = Decimal(principal) * rate / 100 * Decimal(dayCount) / 365
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }
}
