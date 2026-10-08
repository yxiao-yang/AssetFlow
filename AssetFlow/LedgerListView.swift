import SwiftUI

struct LedgerListView: View {
    @Binding var month: Date
    @Binding var selectedCategory: String?
    @Binding var selectedDay: Date?
    @Binding var type: String
    let records: [Expense]
    let pending: [Expense]
    let analytics: LedgerAnalytics
    let add: () -> Void

    private var filtered: [Expense] {
        records.filter { row in
            (selectedCategory == nil || row.category == selectedCategory) &&
            (selectedDay == nil || Calendar.current.isDate(row.date, inSameDayAs: selectedDay!)) &&
            (type == "全部" || row.isIncome == (type == "收入"))
        }
    }
    private var dates: [Date] {
        Set(filtered.map { Calendar.current.startOfDay(for: $0.date) }).sorted(by: >)
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                MonthSelector(month: $month) { clearFilters() }
                summary
                if !pending.isEmpty {
                    NavigationLink {
                        PendingLedgerView(records: pending)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "tray.fill").foregroundStyle(.orange)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(pending.count) 笔截图待确认").font(.subheadline.weight(.medium))
                                Text("核对后入账，暂不计入收支").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }
                }
            }
            .listRowSeparator(.hidden)
            Section {
                Picker("收支筛选", selection: $type) {
                    Text("全部").tag("全部")
                    Text("支出").tag("支出")
                    Text("收入").tag("收入")
                }.pickerStyle(.segmented)
                if selectedCategory != nil || selectedDay != nil {
                    HStack {
                        Text(selectedCategory ?? selectedDay!.formatted(.dateTime.month().day()))
                            .font(.subheadline)
                        Spacer()
                        Button("清除筛选") { clearFilters() }.font(.subheadline)
                    }
                }
            }.listRowSeparator(.hidden)
            if filtered.isEmpty {
                Section {
                    ContentUnavailableView("这个范围还没有记录",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("切换月份或筛选条件，也可以记下第一笔。"))
                }
            } else {
                ForEach(dates, id: \.self) { date in
                    let rows = filtered.filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
                    Section {
                        ForEach(rows) { row in
                            NavigationLink { ExpenseDetailView(expense: row) } label: {
                                LedgerRow(expense: row)
                            }
                        }
                    } header: {
                        dailyHeader(date, rows: rows)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .navigationTitle("资产流")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(filtered.count) 笔记录").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: add) {
                    Label("记一笔", systemImage: "plus").font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 22).padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent).clipShape(Capsule())
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            .background(.regularMaterial)
        }
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                Text("月度支出").font(.subheadline).foregroundStyle(.secondary)
                Text(money(analytics.expense, hidden: false))
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .lineLimit(1).minimumScaleFactor(0.5).monospacedDigit()
            }
            HStack {
                metric("收入", cents: analytics.income, color: LedgerStyle.income)
                Spacer()
                metric("结余", cents: analytics.balance, color: .primary)
                Spacer()
                VStack(alignment: .leading, spacing: 6) {
                    Text("笔数").font(.caption).foregroundStyle(.secondary)
                    Text("\(analytics.monthlyRecords.count)").font(.headline).monospacedDigit()
                }
            }
        }
        .padding(.vertical, 4)
    }
    private func metric(_ title: String, cents: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(money(cents, hidden: false)).font(.subheadline.weight(.semibold))
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.5)
        }
    }
    private func dailyHeader(_ date: Date, rows: [Expense]) -> some View {
        HStack(alignment: .top) {
            Text(date, format: .dateTime.month().day().weekday()).font(.caption.weight(.medium))
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                let expense = rows.filter { !$0.isIncome }.reduce(0) { $0 + $1.amountInCents }
                let income = rows.filter(\.isIncome).reduce(0) { $0 + $1.amountInCents }
                if expense > 0 { Text("支出 " + money(expense, hidden: false)) }
                if income > 0 { Text("收入 " + money(income, hidden: false)) }
            }.font(.caption)
        }.textCase(nil)
    }
    private func clearFilters() { selectedCategory = nil; selectedDay = nil; type = "全部" }
}

struct LedgerRow: View {
    let expense: Expense
    var body: some View {
        HStack(spacing: 12) {
            CategoryIcon(category: expense.category)
            VStack(alignment: .leading, spacing: 5) {
                Text(expense.merchant ?? (expense.note.isEmpty ? expense.category : expense.note))
                    .font(.subheadline.weight(.medium)).lineLimit(1)
                HStack(spacing: 5) {
                    Text(expense.category)
                    if let method = expense.paymentMethod { Text("· " + method) }
                }.font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 5) {
                Text((expense.isIncome ? "+" : "−") + money(expense.amountInCents, hidden: false))
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(expense.isIncome ? LedgerStyle.income : .primary)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(expense.date, format: .dateTime.hour().minute())
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 5)
    }
}

struct PendingLedgerView: View {
    let records: [Expense]
    var body: some View {
        List {
            Section {
                Text("这些记录尚未计入收支。请核对截图、交易状态和金额后再确认。")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            ForEach(records) { row in
                NavigationLink { ExpenseDetailView(expense: row) } label: {
                    VStack(alignment: .leading, spacing: 6) {
                        LedgerRow(expense: row)
                        Text(row.reviewReason ?? "请核对").font(.caption).foregroundStyle(.orange)
                    }
                }
            }
        }.navigationTitle("待确认").navigationBarTitleDisplayMode(.inline)
    }
}
