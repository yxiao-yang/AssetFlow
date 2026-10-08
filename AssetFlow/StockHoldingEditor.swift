import SwiftUI
import SwiftData

struct StockHoldingEditor: View {
    let account: AssetAccount
    private let existing: StockHolding?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @State private var quantity: String
    @State private var cost: String
    @State private var price: String
    @State private var error: String?
    @State private var deleting = false

    init(account: AssetAccount, existing: StockHolding? = nil) {
        self.account = account; self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _symbol = State(initialValue: existing?.symbol ?? "")
        _quantity = State(initialValue: existing?.quantityText ?? "")
        _cost = State(initialValue: existing?.costPriceText ?? "")
        _price = State(initialValue: existing?.priceText ?? "")
    }
    private var code: String? {
        let value = symbol.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = account.currencyCode == "HKD" ? #"^[0-9]{1,5}$"# : #"^[0-9]{6}$"#
        guard value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return account.currencyCode == "HKD" ? String(repeating: "0", count: 5 - value.count) + value : value
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && code != nil &&
        AssetMath.quantity(quantity) != nil && AssetMath.stockPrice(cost) != nil &&
        AssetMath.stockPrice(price) != nil && AssetMath.positionValue(quantity, priceText: price) != nil &&
        AssetMath.positionValue(quantity, priceText: cost) != nil
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("持仓信息 · \(account.currencyCode)") {
                    TextField("股票名称", text: $name)
                    TextField(account.currencyCode == "HKD" ? "港股代码，如 00700" : "股票代码，6 位", text: $symbol)
                        .keyboardType(.numberPad)
                    TextField("持仓数量（股）", text: $quantity).keyboardType(.decimalPad)
                    TextField("成交均价／成本价（每股）", text: $cost).keyboardType(.decimalPad)
                    TextField("当前参考价（每股，手动）", text: $price).keyboardType(.decimalPad)
                    Text("价格最多 4 位小数，数量最多 6 位小数。单笔买入可填成交价；多笔买入请填平均成本价，可使用券商显示的含费用成本。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if valid {
                    Section("持仓预览") {
                        LabeledContent("市值", value: assetMoney(AssetMath.positionValue(quantity, priceText: price)!, currency: account.currencyCode))
                        LabeledContent("成本", value: assetMoney(AssetMath.positionValue(quantity, priceText: cost)!, currency: account.currencyCode))
                        LabeledContent("浮动盈亏", value: assetMoney(AssetMath.positionValue(quantity, priceText: price)! - AssetMath.positionValue(quantity, priceText: cost)!, currency: account.currencyCode))
                    }
                }
                Section {
                    Text("录入后自动计算市值和浮动盈亏。当前参考价需手动更新；调整持有数量后，请另外核对券商可用现金。")
                        .font(.caption).foregroundStyle(.secondary)
                    if existing != nil { Button("移除此持仓", role: .destructive) { deleting = true } }
                }
            }
            .navigationTitle(existing == nil ? "添加持仓" : "核对持仓")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!valid) }
            }
            .confirmationDialog("移除持仓后会更新资产估值，历史记录保留。", isPresented: $deleting, titleVisibility: .visible) {
                Button("移除", role: .destructive) { remove() }
            }
            .alert("未能保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        do {
            let portfolio = try AssetRepository.fetch(context)
            let cash = portfolio.stockCash(account)
            let positions = portfolio.positions(account)
            if positions.contains(where: { $0.symbol == code && $0 !== existing }) {
                error = "该账户已有这只股票，请编辑现有持仓。"; return
            }
            let holding = existing ?? StockHolding(accountID: account.id, name: name, symbol: code!, quantityText: quantity,
                costPriceText: cost, priceText: price)
            holding.name = name.trimmingCharacters(in: .whitespacesAndNewlines); holding.symbol = code!
            holding.quantityText = quantity; holding.costPriceText = cost; holding.priceText = price
            let now = Date()
            account.recordUpdate(at: now, previousDate: portfolio.lastUpdateDate(account))
            holding.updatedAt = now; holding.quoteSource = nil; holding.quoteDate = nil; holding.quoteStatus = nil
            if existing == nil { context.insert(holding) }
            let others = positions.filter { $0 !== holding }.reduce(0) { $0 + $1.marketValue }
            context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: cash + others + holding.marketValue, date: now, note: "持仓与价格核对"))
            try context.save(); dismiss()
        } catch { context.rollback(); self.error = "未能保存持仓，请重试。" }
    }
    private func remove() {
        guard let existing else { return }
        do {
            let portfolio = try AssetRepository.fetch(context)
            let value = portfolio.balance(account) - existing.marketValue
            let now = Date()
            account.recordUpdate(at: now, previousDate: portfolio.lastUpdateDate(account))
            context.delete(existing)
            context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: value, date: now, note: "移除持仓"))
            try context.save(); dismiss()
        } catch { context.rollback(); self.error = "未能移除持仓，请重试。" }
    }
}

struct AssetTransferEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \AssetAccount.createdAt) private var accounts: [AssetAccount]
    @State private var fromID: UUID?
    @State private var toID: UUID?
    @State private var amount = ""
    @State private var received = ""
    @State private var note = ""
    @State private var error: String?
    private var active: [AssetAccount] { accounts.filter { $0.archivedAt == nil } }
    private var from: AssetAccount? { active.first { $0.id == fromID } }
    private var to: AssetAccount? { active.first { $0.id == toID } }
    private var crossCurrency: Bool { from != nil && to != nil && from!.currencyCode != to!.currencyCode }
    private var valid: Bool {
        from != nil && to != nil && fromID != toID && AssetMath.cents(amount, allowZero: false) != nil &&
        (!crossCurrency || AssetMath.cents(received, allowZero: false) != nil)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("转账账户") {
                    Picker("转出", selection: $fromID) {
                        Text("请选择").tag(nil as UUID?)
                        ForEach(active) { Text($0.name + " · " + $0.currencyCode).tag(Optional($0.id)) }
                    }
                    Picker("转入", selection: $toID) {
                        Text("请选择").tag(nil as UUID?)
                        ForEach(active.filter { $0.id != fromID }) { Text($0.name + " · " + $0.currencyCode).tag(Optional($0.id)) }
                    }
                }
                Section("实际到账金额") {
                    TextField("转出金额 · " + (from?.currencyCode ?? ""), text: $amount).keyboardType(.decimalPad)
                    if crossCurrency { TextField("实际转入金额 · " + (to?.currencyCode ?? ""), text: $received).keyboardType(.decimalPad) }
                    TextField("备注（选填）", text: $note)
                    Text("转账不计入日常收支。跨币种分别填写实际扣款与到账金额；证券账户仅转入、转出可用现金。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("账户间转账").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!valid) }
            }
            .onChange(of: fromID) { _, _ in if toID == fromID { toID = nil } }
            .alert("未能转账", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard let from, let to, let cents = AssetMath.cents(amount, allowZero: false) else { return }
        do {
            let portfolio = try AssetRepository.fetch(context)
            let available = from.kind == .stocks ? portfolio.stockCash(from) : portfolio.balance(from)
            guard available >= cents else { error = "转出金额超过已记录的可用余额，请先核对账户。"; return }
            context.insert(AssetTransfer(fromID: from.id, toID: to.id, amountInCents: cents,
                receivedInCents: crossCurrency ? AssetMath.cents(received)! : cents, note: note))
            try context.save(); dismiss()
        } catch { context.rollback(); self.error = "转账记录未能保存，请重试。" }
    }
}
