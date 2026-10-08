import SwiftUI
import SwiftData
import Charts

struct AssetAccountDetail: View {
    let account: AssetAccount
    @Query private var accounts: [AssetAccount]
    @Query(sort: \AssetBalanceSnapshot.date, order: .reverse) private var snapshots: [AssetBalanceSnapshot]
    @Query private var holdings: [StockHolding]
    @Query(sort: \AssetTransfer.date, order: .reverse) private var transfers: [AssetTransfer]
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @Query private var rates: [AssetFXRate]
    @AppStorage("hideLedgerAmounts") private var hidden = false
    @State private var editing = false
    @State private var checking = false
    @State private var addingStock = false
    @State private var selectedStock: StockHolding?
    private var portfolio: AssetPortfolio {
        AssetPortfolio(accounts: accounts, snapshots: snapshots, holdings: holdings,
            transfers: transfers, expenses: expenses, rates: rates)
    }
    private var positions: [StockHolding] { portfolio.positions(account).sorted { $0.marketValue > $1.marketValue } }
    private var latest: AssetBalanceSnapshot? { snapshots.first { $0.accountID == account.id } }

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        AssetAccountIcon(kind: account.kind)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.kind.title).font(.headline)
                            Text(account.currencyCode == "HKD" ? "港币账户" : "人民币账户").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text(assetMoney(portfolio.balance(account), currency: account.currencyCode, hidden: hidden))
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .minimumScaleFactor(0.5).lineLimit(1)
                    if let latest {
                        Text("最近核对：" + latest.date.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption).foregroundStyle(.secondary)
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
                    LabeledContent("股票市值", value: assetMoney(portfolio.stockValue(account), currency: account.currencyCode, hidden: hidden))
                    LabeledContent("可用现金", value: assetMoney(portfolio.stockCash(account), currency: account.currencyCode, hidden: hidden))
                    LabeledContent("持仓成本", value: assetMoney(positions.reduce(0) { $0 + $1.costValue }, currency: account.currencyCode, hidden: hidden))
                    LabeledContent("浮动盈亏", value: assetMoney(positions.reduce(0) { $0 + $1.profit }, currency: account.currencyCode, hidden: hidden))
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
                                    Text(assetMoney(holding.marketValue, currency: account.currencyCode, hidden: hidden))
                                        .font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                }
                                Text(holding.symbol + " · " + (hidden ? "•••" : holding.quantityText) + " 股")
                                    .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Text("现价 " + (hidden ? "•••" : holding.priceText))
                                    Spacer()
                                    Text("盈亏 " + assetMoney(holding.profit, currency: account.currencyCode, hidden: hidden))
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
                if account.kind == .passbook {
                    LabeledContent("存款类型", value: account.depositStyle)
                    if let date = account.maturityDate { LabeledContent("到期日", value: date.formatted(date: .abbreviated, time: .omitted)) }
                }
                if let rate = account.annualRateText {
                    LabeledContent(account.kind == .yuebao ? "七日年化（参考）" : "年利率", value: rate + "%")
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
                                Text((incoming ? "转入 · " : "转出 · ") + (peer?.name ?? "账户"))
                                Spacer()
                                Text(assetMoney(transfer.toID == account.id ? transfer.receivedInCents : transfer.amountInCents, currency: account.currencyCode, hidden: hidden))
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
                        Text(assetMoney(snapshot.amountInCents, currency: account.currencyCode, hidden: hidden)).font(.subheadline)
                    }
                }
                Text("余额核对替代该时点之前的余额推算；更早的收支仍保留在账本中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(account.name).navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { AssetAccountEditor(existing: account) }
        .sheet(isPresented: $checking) { AssetBalanceEditor(account: account) }
        .sheet(isPresented: $addingStock) { StockHoldingEditor(account: account) }
        .sheet(item: $selectedStock) { StockHoldingEditor(account: account, existing: $0) }
    }
}
