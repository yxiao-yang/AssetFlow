import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @State private var ledgerPath: [LedgerRoute] = []
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
    @State private var showingSettings = false
    @AppStorage(AppAppearance.storageKey) private var appearance = AppAppearance.system.rawValue

    init() {
        #if DEBUG
        _showingSettings = State(initialValue: CommandLine.arguments.contains("--demo-settings"))
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
            NavigationStack(path: $ledgerPath) {
                LedgerListView(month: $month, selectedCategory: $category, selectedDay: $day, type: $filterType,
                    records: monthRecords, pending: expenses.filter(\.needsConfirmation), analytics: analytics,
                    add: { showingEntry = true }, openPending: { ledgerPath.append(.pending) })
                    .toolbar { SettingsToolbar(showing: $showingSettings) }
                    .navigationDestination(for: LedgerRoute.self) { route in
                        switch route {
                        case .pending: PendingLedgerView()
                        case .record(let id):
                            if let expense = expenses.first(where: { $0.persistentModelID == id }) {
                                ExpenseDetailView(expense: expense, onDeleted: returnAfterDeletion)
                            } else {
                                ContentUnavailableView("记录已删除", systemImage: "doc")
                            }
                        }
                    }
            }
            .tabItem { Label("明细", systemImage: "list.bullet.rectangle") }.tag(0)
            NavigationStack {
                LedgerChartsView(month: $month, analytics: analytics, records: monthRecords)
                    .toolbar { SettingsToolbar(showing: $showingSettings) }
            }
            .tabItem { Label("图表", systemImage: "chart.pie") }.tag(1)
            NavigationStack {
                LedgerCalendarView(month: $month, analytics: analytics) { selected in
                    day = selected; category = nil; filterType = "全部"; tab = 0
                }
                .toolbar { SettingsToolbar(showing: $showingSettings) }
            }
            .tabItem { Label("日历", systemImage: "calendar") }.tag(2)
            NavigationStack { assetPage.toolbar { SettingsToolbar(showing: $showingSettings) } }
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
        .sheet(isPresented: $showingSettings) {
            NavigationStack {
                SettingsView()
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("关闭") { showingSettings = false }
                        }
                    }
            }
        }
        .background {
            AppAppearanceBridge(appearance: AppAppearance(rawValue: appearance) ?? .system)
                .frame(width: 0, height: 0).allowsHitTesting(false)
        }
        .onChange(of: expenses.filter(\.needsConfirmation).isEmpty) { _, empty in
            if empty, ledgerPath.contains(.pending) { ledgerPath.removeAll() }
        }
        .onChange(of: month) { _, _ in category = nil; day = nil; filterType = "全部" }
    }
    private func returnAfterDeletion() {
        if ledgerPath.contains(.pending) {
            let pending = FetchDescriptor<Expense>(predicate: #Predicate { $0.needsConfirmation })
            // The save has completed; query the store rather than a possibly stale view snapshot.
            if (try? context.fetchCount(pending)) == 0 { ledgerPath.removeAll() }
            else { ledgerPath = [.pending] }
        } else if !ledgerPath.isEmpty {
            ledgerPath.removeLast()
        }
    }
}

#Preview {
    ContentView().modelContainer(for: [Expense.self, AssetAccount.self, AssetBalanceSnapshot.self, StockHolding.self, AssetTransfer.self, AssetFXRate.self, TermDeposit.self], inMemory: true)
}
