import SwiftUI

func money(_ cents: Int, hidden: Bool = false) -> String {
    hidden ? "••••" : (Decimal(cents) / 100).formatted(.currency(code: "CNY"))
}

enum LedgerStyle {
    static let accent = Color(red: 0.20, green: 0.43, blue: 0.36)
    static let income = Color(red: 0.15, green: 0.49, blue: 0.38)
    static let expense = Color(red: 0.77, green: 0.32, blue: 0.24)
    static func icon(_ category: String) -> String {
        switch category {
        case "餐饮": "fork.knife"
        case "交通": "tram.fill"
        case "购物": "bag.fill"
        case "住房": "house.fill"
        case "娱乐": "gamecontroller.fill"
        case "医疗": "cross.case.fill"
        case "工资": "briefcase.fill"
        case "奖金": "gift.fill"
        case "兼职": "laptopcomputer"
        case "理财收益": "chart.line.uptrend.xyaxis"
        default: "square.grid.2x2.fill"
        }
    }
    static func color(_ category: String) -> Color {
        switch category {
        case "餐饮": .orange
        case "交通": .blue
        case "购物": .purple
        case "住房": .teal
        case "娱乐": .pink
        case "医疗": .red
        case "工资", "奖金", "兼职", "理财收益": income
        default: .gray
        }
    }
}

struct CategoryIcon: View {
    let category: String
    var body: some View {
        Image(systemName: LedgerStyle.icon(category))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(LedgerStyle.color(category))
            .frame(width: 42, height: 42)
            .background(LedgerStyle.color(category).opacity(0.11), in: RoundedRectangle(cornerRadius: 14))
            .accessibilityHidden(true)
    }
}

struct MonthSelector: View {
    @Binding var month: Date
    let reset: () -> Void
    private var isCurrent: Bool { Calendar.current.isDate(month, equalTo: .now, toGranularity: .month) }
    var body: some View {
        HStack {
            Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 40, height: 44) }
                .accessibilityLabel("上个月")
            Spacer()
            VStack(spacing: 3) {
                Text(month, format: .dateTime.year().month()).font(.headline)
                if !isCurrent {
                    Button("回到本月") { month = .now; reset() }.font(.caption)
                }
            }
            Spacer()
            Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 40, height: 44) }
                .disabled(isCurrent).accessibilityLabel("下个月")
        }
        // Keep each control independent when this selector sits inside a List row.
        .buttonStyle(.borderless)
    }
    private func move(_ value: Int) {
        if let start = Calendar.current.dateInterval(of: .month, for: month)?.start,
           let next = Calendar.current.date(byAdding: .month, value: value, to: start) {
            month = next
            reset()
        }
    }
}
