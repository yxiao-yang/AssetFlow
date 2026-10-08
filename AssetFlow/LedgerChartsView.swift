import SwiftUI
import Charts

struct LedgerChartsView: View {
    @Binding var month: Date
    let hidden: Bool
    let analytics: LedgerAnalytics
    let selectCategory: (String, Bool) -> Void
    @State private var isIncome = false
    private var categories: [CategoryTotal] { analytics.categories(isIncome: isIncome) }
    private var total: Int { isIncome ? analytics.income : analytics.expense }

    var body: some View {
        List {
            Section {
                MonthSelector(month: $month) {}
                Picker("统计类型", selection: $isIncome) {
                    Text("支出").tag(false)
                    Text("收入").tag(true)
                }.pickerStyle(.segmented)
            }.listRowSeparator(.hidden)
            if hidden {
                Section {
                    ContentUnavailableView("金额已隐藏", systemImage: "eye.slash",
                        description: Text("在明细页开启金额显示后查看图表。"))
                }
            } else if categories.isEmpty {
                Section {
                    ContentUnavailableView("暂无统计数据", systemImage: "chart.pie",
                        description: Text("这个月还没有已确认的\(isIncome ? "收入" : "支出")。"))
                }
            } else {
                Section("分类构成") {
                    Chart(categories) { item in
                        SectorMark(angle: .value("金额", Double(item.cents) / 100),
                            innerRadius: .ratio(0.70), angularInset: 2)
                            .cornerRadius(5)
                            .foregroundStyle(LedgerStyle.color(item.category))
                    }
                    .frame(height: 230)
                    .chartBackground { proxy in
                        GeometryReader { geometry in
                            if let frame = proxy.plotFrame {
                                let rect = geometry[frame]
                                VStack(spacing: 6) {
                                    Text(isIncome ? "总收入" : "总支出").font(.caption).foregroundStyle(.secondary)
                                    Text(money(total)).font(.headline).monospacedDigit()
                                }.position(x: rect.midX, y: rect.midY)
                            }
                        }
                    }
                    .accessibilityLabel("分类构成，详细金额请查看下方分类排行")
                }
                Section("每日\(isIncome ? "收入" : "支出")") {
                    Chart(analytics.days) { day in
                        BarMark(x: .value("日期", day.date, unit: .day),
                            y: .value("金额", Double(isIncome ? day.income : day.expense) / 100))
                            .foregroundStyle(LedgerStyle.accent)
                            .cornerRadius(3)
                    }
                    .frame(height: 180)
                    .chartXAxis { AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                        AxisGridLine(); AxisValueLabel(format: .dateTime.day())
                    } }
                    .chartYAxisLabel("元")
                }
                Section("分类排行 · 点击查看明细") {
                    ForEach(categories) { item in
                        Button { selectCategory(item.category, isIncome) } label: {
                            VStack(spacing: 10) {
                                HStack(spacing: 12) {
                                    CategoryIcon(category: item.category)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.category).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                        Text("\(item.count) 笔 · " + (Double(item.cents) / Double(total)).formatted(.percent.precision(.fractionLength(1))))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(money(item.cents)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                                }
                                ProgressView(value: Double(item.cents), total: Double(total))
                                    .tint(LedgerStyle.color(item.category))
                            }.padding(.vertical, 5)
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle("收支分析")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
}

struct LedgerCalendarView: View {
    @Binding var month: Date
    let hidden: Bool
    let analytics: LedgerAnalytics
    let selectDay: (Date) -> Void
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
    private var paddingDays: Int {
        guard let first = analytics.days.first else { return 0 }
        let cal = Calendar.current
        return (cal.component(.weekday, from: first.date) - cal.firstWeekday + 7) % 7
    }
    private var weekdays: [String] {
        var cal = Calendar.current
        cal.locale = Locale(identifier: "zh_CN")
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        let offset = cal.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset])
    }
    var body: some View {
        List {
            Section {
                MonthSelector(month: $month) {}
                HStack {
                    Label("支出", systemImage: "minus.circle.fill").foregroundStyle(LedgerStyle.expense)
                    Spacer()
                    Label("收入", systemImage: "plus.circle.fill").foregroundStyle(LedgerStyle.income)
                }.font(.caption)
                LazyVGrid(columns: columns, spacing: 9) {
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { _, name in
                        Text(name).font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(0..<paddingDays, id: \.self) { _ in Color.clear.frame(height: 56) }
                    ForEach(analytics.days) { day in
                        Button { selectDay(day.date) } label: {
                            VStack(spacing: 5) {
                                Text("\(Calendar.current.component(.day, from: day.date))")
                                    .font(.subheadline.weight(Calendar.current.isDateInToday(day.date) ? .bold : .regular))
                                    .foregroundStyle(Calendar.current.isDateInToday(day.date) ? LedgerStyle.accent : .primary)
                                if day.expense > 0 { calendarAmount(day.expense, color: LedgerStyle.expense) }
                                if day.income > 0 { calendarAmount(day.income, color: LedgerStyle.income) }
                                if day.count == 0 { Text(" ").font(.caption2) }
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .top)
                            .padding(.top, 7)
                            .background(day.count > 0 ? LedgerStyle.accent.opacity(0.06) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(day.date.formatted(date: .complete, time: .omitted) + "，\(day.count) 笔记录")
                    }
                }
                Text("点击日期查看当天流水。日历金额单位为元。")
                    .font(.caption).foregroundStyle(.secondary)
            }.listRowSeparator(.hidden)
            Section("月度小结") {
                LabeledContent("支出", value: money(analytics.expense, hidden: hidden))
                LabeledContent("收入", value: money(analytics.income, hidden: hidden))
                LabeledContent("结余", value: money(analytics.balance, hidden: hidden))
                LabeledContent("记账天数", value: "\(analytics.days.filter { $0.count > 0 }.count) 天")
            }
        }
        .navigationTitle("记账日历")
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
    }
    private func calendarAmount(_ cents: Int, color: Color) -> some View {
        Text(hidden ? "•••" : (Double(cents) / 100).formatted(.number.notation(.compactName).precision(.fractionLength(0...1))))
            .font(.system(size: 9, weight: .medium)).foregroundStyle(color)
            .lineLimit(1).minimumScaleFactor(0.6)
    }
}
