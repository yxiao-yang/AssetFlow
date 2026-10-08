import SwiftUI
import SwiftData

struct AssetAccountEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let existing: AssetAccount?
    @State private var name: String
    @State private var kind: AssetKind
    @State private var currency: String
    @State private var institution: String
    @State private var lastFour: String
    @State private var note: String
    @State private var depositStyle: String
    @State private var annualRate: String
    @State private var maturity: Date
    @State private var balance = ""
    @State private var failed = false

    init(existing: AssetAccount? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind ?? .debitCard)
        _currency = State(initialValue: existing?.currencyCode ?? "CNY")
        _institution = State(initialValue: existing?.institution ?? "")
        _lastFour = State(initialValue: existing?.lastFour ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _depositStyle = State(initialValue: existing?.depositStyle ?? "活期")
        _annualRate = State(initialValue: existing?.annualRateText ?? "")
        _maturity = State(initialValue: existing?.maturityDate ?? .now)
    }
    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        (lastFour.isEmpty || lastFour.range(of: #"^[0-9]{4}$"#, options: .regularExpression) != nil) &&
        (existing != nil || AssetMath.cents(balance) != nil) &&
        (annualRate.isEmpty || (AssetMath.stockPrice(annualRate) != nil && AssetMath.stockPrice(annualRate)! <= 100))
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("账户资料") {
                    TextField("名称，如 招商银行储蓄卡", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(AssetKind.allCases) { Text($0.title).tag($0) }
                    }.disabled(existing != nil)
                    Picker("币种", selection: $currency) {
                        Text("人民币 CNY").tag("CNY")
                        Text("港币 HKD").tag("HKD")
                    }.disabled(existing != nil)
                    TextField("银行／券商／机构（选填）", text: $institution)
                    if kind == .debitCard || kind == .passbook {
                        TextField("账号尾号 4 位（选填）", text: $lastFour).keyboardType(.numberPad)
                        Text("只保存尾号，用于识别截图扣款账户；不需要完整账号。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("备注（选填）", text: $note, axis: .vertical)
                }
                if kind == .passbook {
                    Section("存款信息") {
                        Picker("存款类型", selection: $depositStyle) {
                            Text("活期").tag("活期")
                            Text("定期").tag("定期")
                        }
                        if depositStyle == "定期" { DatePicker("到期日", selection: $maturity, displayedComponents: .date) }
                        TextField("年利率 %（选填）", text: $annualRate).keyboardType(.decimalPad)
                    }
                } else if kind == .yuebao {
                    Section("收益参考") {
                        TextField("七日年化 %（选填）", text: $annualRate).keyboardType(.decimalPad)
                        Text("手动记录参考值，不据此自动计入收益。实际收益请核对余额或记录收入。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if existing == nil {
                    Section(kind == .stocks ? "当前可用现金" : "当前余额") {
                        TextField("金额，可填 0", text: $balance).keyboardType(.decimalPad)
                        Text(kind == .stocks ? "这里只填证券账户现金，创建后逐只添加股票，避免重复计算市值。" : "以现在的余额作为起点；关联账户后发生的收支会更新余额。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? "添加资产账户" : "编辑账户资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!valid) }
            }
            .onChange(of: kind) { _, value in
                if existing == nil { currency = value == .stocks ? "HKD" : "CNY" }
            }
            .alert("保存失败，请重试", isPresented: $failed) { Button("好", role: .cancel) {} }
        }
    }
    private func save() {
        let account = existing ?? AssetAccount(name: name, kind: kind)
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.depositStyle = depositStyle
        account.annualRateText = annualRate.isEmpty ? nil : annualRate
        account.maturityDate = kind == .passbook && depositStyle == "定期" ? maturity : nil
        account.institution = institution; account.lastFour = lastFour; account.note = note
        if existing == nil {
            account.currencyCode = currency
            context.insert(account)
            context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: AssetMath.cents(balance)!,
                date: account.createdAt, note: kind == .stocks ? "录入可用现金" : "期初余额"))
        }
        do { try context.save(); dismiss() } catch { context.rollback(); failed = true }
    }
}

struct AssetBalanceEditor: View {
    let account: AssetAccount
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var note = ""
    @State private var failed = false
    var body: some View {
        NavigationStack {
            Form {
                Section(account.kind == .stocks ? "当前可用现金 · \(account.currencyCode)" : "当前账户余额 · \(account.currencyCode)") {
                    TextField("输入核对后的金额", text: $amount).keyboardType(.decimalPad)
                    TextField("核对说明（选填）", text: $note)
                    Text("此次核对会更新当前余额并保留旧记录，不会记作收入或支出。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("余额核对").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(AssetMath.cents(amount) == nil) }
            }
            .alert("核对失败，请重试", isPresented: $failed) { Button("好", role: .cancel) {} }
        }
    }
    private func save() {
        do {
            let portfolio = try AssetRepository.fetch(context)
            let value = AssetMath.cents(amount)! + (account.kind == .stocks ? portfolio.stockValue(account) : 0)
            context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: value,
                note: note.isEmpty ? "余额核对" : note))
            try context.save(); dismiss()
        } catch { context.rollback(); failed = true }
    }
}

struct AssetRateEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var rate = ""
    @State private var failed = false
    @State private var fetching = false
    @State private var fetchedRate: String?
    @State private var marketDate: String?
    @State private var source = "手动录入"
    var body: some View {
        NavigationStack {
            Form {
                Section("1 港币折合多少人民币") {
                    TextField("输入 HKD → CNY 汇率", text: $rate).keyboardType(.decimalPad)
                        .onChange(of: rate) { _, value in
                            if value != fetchedRate { source = "手动录入"; marketDate = nil }
                        }
                    Button(fetching ? "正在获取…" : "获取最新参考汇率") {
                        Task { await fetch() }
                    }.disabled(fetching)
                    if let marketDate { Text("参考汇率日期：" + marketDate).font(.caption).foregroundStyle(.secondary) }
                    Text("参考汇率按日更新，不是实时换汇成交价。来源：Frankfurter。")
                        .font(.caption).foregroundStyle(.secondary)
                    Text("不会改动港币账户原始金额，历史换算保留当时记录的汇率。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("换算汇率").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        let saved = AssetFXRate(rateText: rate, source: source)
                        saved.marketDate = marketDate
                        context.insert(saved)
                        do { try context.save(); dismiss() } catch { context.rollback(); failed = true }
                    }.disabled(AssetMath.exchangeRate(rate) == nil)
                }
            }
            .alert("操作未完成，请重试或手动设置汇率", isPresented: $failed) { Button("好", role: .cancel) {} }
        }
    }
    @MainActor
    private func fetch() async {
        fetching = true
        defer { fetching = false }
        do {
            let fetched = try await AssetFXClient.fetchHKD()
            var raw = fetched.rate
            var rounded = Decimal()
            NSDecimalRound(&rounded, &raw, 8, .plain)
            let text = NSDecimalNumber(decimal: rounded).stringValue
            fetchedRate = text
            rate = text
            marketDate = fetched.date
            source = "Frankfurter 每日参考汇率"
        } catch { failed = true }
    }
}
