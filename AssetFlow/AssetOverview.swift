import SwiftUI
import SwiftData
import Charts

struct AssetOverview: View {
    @Query(sort: \AssetAccount.createdAt) private var accounts: [AssetAccount]
    @Query private var snapshots: [AssetBalanceSnapshot]
    @Query private var deposits: [TermDeposit]
    @Query private var holdings: [StockHolding]
    @Query private var transfers: [AssetTransfer]
    @Query private var expenses: [Expense]
    @AppStorage("assetHistoryRange") private var historyRangeRaw = AssetHistoryRange.quarter.rawValue
    private var historyRange: AssetHistoryRange { AssetHistoryRange(rawValue: historyRangeRaw) ?? .quarter }
    private var history: [AssetHistoryPoint] { portfolio.history(in: historyRange) }
    @State private var creating = false
    @State private var transferring = false

    private var portfolio: AssetPortfolio {
        AssetPortfolio(accounts: accounts, snapshots: snapshots, holdings: holdings,
            transfers: transfers, expenses: expenses, deposits: deposits)
    }
    private var sorted: [AssetAccount] {
        portfolio.activeAccounts.sorted { portfolio.balance($0) > portfolio.balance($1) }
    }
    private var composition: [(kind: AssetKind, value: Int)] {
        AssetKind.selectable.compactMap { kind in
            let value = sorted.filter { $0.kind.category == kind }.reduce(0) { $0 + max(0, portfolio.balance($1)) }
            return value > 0 ? (kind, value) : nil
        }.sorted { $0.value > $1.value }
    }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("总资产 · 人民币").font(.subheadline).foregroundStyle(.secondary)
                        Text(assetMoney(portfolio.total, hidden: false))
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .lineLimit(1).minimumScaleFactor(0.5)
                    }.padding(.vertical, 8)
                    HStack {
                        Button { creating = true } label: { Label("添加账户", systemImage: "plus.circle") }
                        Spacer()
                        Button { transferring = true } label: { Label("账户转账", systemImage: "arrow.left.arrow.right") }
                            .disabled(sorted.count < 2)
                    }.font(.subheadline).buttonStyle(.borderless)

                }
            }.listRowSeparator(.hidden)
            if sorted.isEmpty {
                Section {
                    ContentUnavailableView("把分散的资产放在一起", systemImage: "wallet.pass",
                        description: Text("选择账户大类，自定义名称并录入当前余额。"))
                }
            } else {
                Section("账户明细") {
                    ForEach(sorted) { account in
                        NavigationLink { AssetAccountDetail(account: account) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    AssetAccountIcon(kind: account.kind.category)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(account.name).font(.subheadline.weight(.semibold))
                                        Text(account.kind.category.title + (account.lastFour.isEmpty ? "" : " · 尾号 " + account.lastFour))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    VStack(alignment: .trailing, spacing: 5) {
                                        Text(assetMoney(portfolio.balance(account), hidden: false))
                                            .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.5)
                                            .foregroundStyle(portfolio.balance(account) < 0 ? .red : .primary)

                                    }
                                }
                                Text("上次更新时间 " + portfolio.lastUpdateDate(account).formatted(date: .numeric, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary).padding(.leading, 56)
                                }.padding(.vertical, 4)
                        }
                    }
                }
                if !composition.isEmpty {
                    Section("资产分布") {
                        Chart(Array(composition.enumerated()), id: \.offset) { _, item in
                            SectorMark(angle: .value("资产", Double(item.value) / 100), innerRadius: .ratio(0.72), angularInset: 2)
                                .cornerRadius(4).foregroundStyle(item.kind.color)
                        }.frame(height: 190)
                        ForEach(Array(composition.enumerated()), id: \.offset) { _, item in
                            HStack {
                                Circle().fill(item.kind.color).frame(width: 8, height: 8)
                                Text(item.kind.title).font(.subheadline)
                                Spacer()
                                Text(assetMoney(item.value)).font(.subheadline)
                                Text((Double(item.value) / Double(max(1, composition.reduce(0) { $0 + $1.value })))
                                    .formatted(.percent.precision(.fractionLength(1))))
                                    .font(.caption).foregroundStyle(.secondary).frame(width: 50, alignment: .trailing)
                            }
                        }
                        Text("占比仅计算正余额；负余额请在账户中核对。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("资产变化") {
                        Picker("时间范围", selection: $historyRangeRaw) {
                            ForEach(AssetHistoryRange.allCases) { range in
                                Text(range.title).tag(range.rawValue)
                            }
                        }.pickerStyle(.segmented)
                        if history.count > 1 {
                            Chart(history) { point in
                                LineMark(x: .value("日期", point.date), y: .value("人民币", Double(point.cents) / 100))
                                    .foregroundStyle(LedgerStyle.accent)
                            }.frame(height: 150).chartYAxisLabel("元")
                        } else {
                            Text("这个时间段记录不足，积累记录后显示趋势").foregroundStyle(.secondary)
                        }
                        Text("仅展示已录入的历史，1 年按近 365 天计算。估值更新不会改写之前的余额。新增资产也会引起总额变化，不能把趋势变化全部当作投资收益。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                let unlinked = expenses.filter { !$0.needsConfirmation && $0.accountID == nil }
                if !unlinked.isEmpty {
                    Section {
                        NavigationLink {
                            List(unlinked) { expense in
                                NavigationLink { ExpenseDetailView(expense: expense) } label: {
                                    LedgerRow(expense: expense)
                                }
                            }.navigationTitle("未关联账户的收支").navigationBarTitleDisplayMode(.inline)
                        } label: {
                            Label("\(unlinked.count) 笔收支未关联账户", systemImage: "link.badge.plus")
                                .font(.subheadline)
                        }
                        Text("这些记录已计入账本收支，但未改变任何资产账户余额。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

            }
        }
        .listSectionSpacing(14)
        .navigationTitle("我的资产").navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $creating) { AssetAccountEditor() }
        .sheet(isPresented: $transferring) { AssetTransferEditor() }
    }
}
