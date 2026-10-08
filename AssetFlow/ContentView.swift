import SwiftUI
import SwiftData

struct ContentView: View {
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    #if DEBUG
    @Query private var demoAccounts: [AssetAccount]
    #endif
    @State private var month = Date()
    @State private var tab = 0
    @State private var category: String?
    @State private var day: Date?
    @State private var filterType = "全部"
    @State private var showingEntry = false
    @AppStorage("hideLedgerAmounts") private var hidden = false

    init() {
        #if DEBUG
        _tab = State(initialValue: CommandLine.arguments.contains("--demo-charts") ? 1 :
            CommandLine.arguments.contains("--demo-calendar") ? 2 :
            (CommandLine.arguments.contains("--demo-assets") || CommandLine.arguments.contains("--demo-term-deposits")) ? 3 : 0)
        #endif
    }

    @ViewBuilder
    private var assetPage: some View {
        #if DEBUG
        if CommandLine.arguments.contains("--demo-term-deposits"), let account = demoAccounts.first(where: { $0.managesTermDeposits }) {
            AssetAccountDetail(account: account)
        } else { AssetOverview() }
        #else
        AssetOverview()
        #endif
    }
    private var analytics: LedgerAnalytics {
        LedgerAnalytics(records: expenses.map {
            LedgerRecord(amountInCents: $0.amountInCents, category: $0.category, date: $0.date,
                isIncome: $0.isIncome, needsConfirmation: $0.needsConfirmation)
        }, month: month)
    }
    private var monthRecords: [Expense] {
        expenses.filter { !$0.needsConfirmation && Calendar.current.isDate($0.date, equalTo: month, toGranularity: .month) }
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                LedgerListView(month: $month, hidden: $hidden, selectedCategory: $category, selectedDay: $day, type: $filterType,
                    records: monthRecords, pending: expenses.filter(\.needsConfirmation), analytics: analytics,
                    add: { showingEntry = true })
            }
            .tabItem { Label("明细", systemImage: "list.bullet.rectangle") }.tag(0)
            NavigationStack {
                LedgerChartsView(month: $month, hidden: hidden, analytics: analytics) { selected, income in
                    category = selected; day = nil; filterType = income ? "收入" : "支出"; tab = 0
                }
            }
            .tabItem { Label("图表", systemImage: "chart.pie") }.tag(1)
            NavigationStack {
                LedgerCalendarView(month: $month, hidden: hidden, analytics: analytics) { selected in
                    day = selected; category = nil; filterType = "全部"; tab = 0
                }
            }
            .tabItem { Label("日历", systemImage: "calendar") }.tag(2)
            NavigationStack { assetPage }
                .tabItem { Label("资产", systemImage: "wallet.pass") }.tag(3)
        }
        .tint(LedgerStyle.accent)
        .environment(\.locale, Locale(identifier: "zh_CN"))
        .sheet(isPresented: $showingEntry) {
            ExpenseEntryView { expense in
                month = expense.date
                category = nil
                day = nil
                filterType = "全部"
                tab = 0
            }
        }
        .onChange(of: month) { _, _ in category = nil; day = nil; filterType = "全部" }
    }
}

#Preview {
    ContentView().modelContainer(for: [Expense.self, AssetAccount.self, AssetBalanceSnapshot.self, StockHolding.self, AssetTransfer.self, AssetFXRate.self, TermDeposit.self], inMemory: true)
}
