import SwiftUI
import SwiftData
import Charts

struct AssetAccountDetail: View {
    let account: AssetAccount
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var deleting = false
    @State private var deletionError = false
    @Query private var accounts: [AssetAccount]
    @Query(sort: \AssetBalanceSnapshot.date, order: .reverse) private var snapshots: [AssetBalanceSnapshot]
    @Query private var holdings: [StockHolding]
    @Query(sort: \AssetTransfer.date, order: .reverse) private var transfers: [AssetTransfer]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @AppStorage("hideLedgerAmounts") private var hidden = false
    @State private var editing = false
    @State private var checking = false
    @State private var addingStock = false
    @State private var selectedStock: StockHolding?
    private var portfolio: AssetPortfolio {
        AssetPortfolio(accounts: accounts, snapshots: snapshots, holdings: holdings,
            transfers: transfers, expenses: expenses)
    }
    private var positions: [StockHolding] { portfolio.positions(account).sorted { $0.marketValue > $1.marketValue } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        AssetAccountIcon(kind: account.kind.category)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.kind.category.title).font(.headline)
                            Text("人民币账户").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(assetMoney(portfolio.balance(account), hidden: hidden))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    Text("上次更新时间：" + portfolio.lastUpdateDate(account).formatted(date: .numeric, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    if let previous = account.previousUpdatedAt {
                        Text("前次更新时间：" + previous.formatted(date: .numeric, time: .shortened))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    if portfolio.balance(account) < 0 {
                        Text("余额为负，请检查期初余额、账户关联和遗漏的入账。")
                            .font(.caption).foregroundStyle(.red)
                    }
                }.padding(.vertical, 6)
                Button(account.kind == .stocks ? "核对证券账户可用现金" : "核对当前余额") { checking = true }
            }
            if account.kind == .stocks {
                Section("证券账户构成") {
                    LabeledContent("股票市值", value: assetMoney(portfolio.stockValue(account), hidden: hidden))
                    LabeledContent("可用现金", value: assetMoney(portfolio.stockCash(account), hidden: hidden))
                    LabeledContent("持仓成本", value: assetMoney(positions.reduce(0) { $0 + $1.costValue }, hidden: hidden))
                    LabeledContent("浮动盈亏", value: assetMoney(positions.reduce(0) { $0 + $1.profit }, hidden: hidden))
                    Text("浮动盈亏 = 当前市值 − 持仓成本，未计入已实现收益、分红与未纳入成本的费用。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("股票持仓") {
                    ForEach(positions) { holding in
                        Button { selectedStock = holding } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Text(holding.name).font(.headline).foregroundStyle(.primary)
                                    Spacer()
                                    Text(assetMoney(holding.marketValue, hidden: hidden))
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                }
                                Text(holding.symbol + " · " + (hidden ? "•••" : holding.quantityText) + " 股")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Text("现价 " + (hidden ? "•••" : holding.priceText))
                                    Spacer()
                                    Text("盈亏 " + assetMoney(holding.profit, hidden: hidden))
                                        .foregroundStyle(holding.profit >= 0 ? LedgerStyle.income : LedgerStyle.expense)
                                }.font(.caption)
                                if holding.costValue > 0 {
                                    Text("盈亏率 " + (hidden ? "•••" : (Double(holding.profit) / Double(holding.costValue)).formatted(.percent.precision(.fractionLength(2)))))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Text((holding.quoteSource ?? "手动价格") + " · " + (holding.quoteStatus ?? "未接入实时行情"))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Text("价格时间：" + (holding.quoteDate ?? holding.updatedAt).formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }.padding(.vertical, 6)
                        }.buttonStyle(.plain)
                    }
                    Button { addingStock = true } label: { Label("添加股票持仓", systemImage: "plus.circle") }
                }
            }
            Section("账户资料") {
                LabeledContent("机构", value: account.institution.isEmpty ? "未填写" : account.institution)
                if !account.lastFour.isEmpty { LabeledContent("尾号", value: account.lastFour) }
                if account.kind == .passbook || account.maturityDate != nil {
                    LabeledContent("存款类型", value: account.depositStyle)
                    if let date = account.maturityDate { LabeledContent("到期日", value: date.formatted(date: .abbreviated, time: .omitted)) }
                }
                if let rate = account.annualRateText {
                    LabeledContent(account.kind == .yuebao ? "七日年化（参考）" : "年利率／收益率参考", value: rate + "%")
                }
                if !account.note.isEmpty { Text(account.note).font(.subheadline) }
                Button("编辑账户资料") { editing = true }
            }
            let linked = expenses.filter { $0.accountID == account.id && !$0.needsConfirmation }
            if !linked.isEmpty {
                Section("关联收支") {
                    ForEach(linked) { expense in
                        NavigationLink { ExpenseDetailView(expense: expense) } label: { LedgerRow(expense: expense, hidden: hidden) }
                    }
                }
            }
            let movements = transfers.filter { $0.fromID == account.id || $0.toID == account.id }
            if !movements.isEmpty {
                Section("账户间转账 · 不计入收支") {
                    ForEach(movements) { transfer in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                let incoming = transfer.toID == account.id
                                let peer = accounts.first { $0.id == (incoming ? transfer.fromID : transfer.toID) }
                                Text((incoming ? "转入 · " : "转出 · ") + (peer?.name ?? "已删除账户"))
                                Spacer()
                                Text(assetMoney(transfer.toID == account.id ? transfer.receivedInCents : transfer.amountInCents, hidden: hidden))
                            }.font(.subheadline)
                            Text(transfer.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                            if !transfer.note.isEmpty { Text(transfer.note).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                }
            }
            Section("余额与估值记录") {
                ForEach(snapshots.filter { $0.accountID == account.id }) { snapshot in
                    HStack {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(snapshot.note).font(.subheadline)
                            Text(snapshot.date, format: .dateTime.year().month().day().hour().minute())
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(assetMoney(snapshot.amountInCents, hidden: hidden)).font(.subheadline)
                    }
                }
                Text("余额核对替代该时点之前的余额推算；更早的收支仍保留在账本中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section {
                Button("删除账户", role: .destructive) { deleting = true }
            } footer: {
                Text("删除账户及其持仓、余额核对记录，账本收支保留并解除关联。其他账户中的转账记录保留。")
            }
        }
        .navigationTitle(account.name).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("删除", role: .destructive) { deleting = true }
            }
        }
        .confirmationDialog("删除账户“" + account.name + "”？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除账户", role: .destructive) {
                do { try AssetRepository.deleteAccount(account, in: context); dismiss() }
                catch { deletionError = true }
            }
        } message: {
            Text("账户、持仓和余额核对记录将被删除。账本收支保留并解除关联，其他账户的转账记录和余额保留。")
        }
        .alert("删除失败，请重试", isPresented: $deletionError) { Button("好", role: .cancel) {} }
        .sheet(isPresented: $editing) { AssetAccountEditor(existing: account) }
        .sheet(isPresented: $checking) { AssetBalanceEditor(account: account) }
        .sheet(isPresented: $addingStock) { StockHoldingEditor(account: account) }
        .sheet(item: $selectedStock) { StockHoldingEditor(account: account, existing: $0) }
    }
}
