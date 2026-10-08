import Foundation

enum AssetHistoryRange: String, CaseIterable, Identifiable {
    case week, month, quarter, year, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .week: "7 天"
        case .month: "30 天"
        case .quarter: "90 天"
        case .year: "1 年"
        case .all: "全部"
        }
    }
    func startDate(until end: Date, calendar: Calendar = .current) -> Date? {
        let days: Int
        switch self {
        case .week: days = 7
        case .month: days = 30
        case .quarter: days = 90
        case .year: days = 365
        case .all: return nil
        }
        return calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: end))
    }
}
