import SwiftUI
import SwiftData

struct AssetAccountEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    private let existing: AssetAccount?
    @State private var name: String
    @State private var kind: AssetKind
    @State private var institution: String
    @State private var lastFour: String
    @State private var note: String
    @State private var annualRate: String
    @State private var maturity: Date
    @State private var managesTerms: Bool
    @Query private var deposits: [TermDeposit]
    @State private var hasMaturity: Bool
    @State private var balance = ""
    @State private var failed = false
    @Query private var snapshots: [AssetBalanceSnapshot]
    private var lastUpdate: Date? {
        guard let existing else { return nil }
        return max(existing.updatedAt ?? existing.createdAt,
            snapshots.filter { $0.accountID == existing.id }.map(\.date).max() ?? existing.createdAt)
    }

    init(existing: AssetAccount? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _kind = State(initialValue: existing?.kind.category ?? .funds)
        _institution = State(initialValue: existing?.institution ?? "")
        _lastFour = State(initialValue: existing?.lastFour ?? "")
        _note = State(initialValue: existing?.note ?? "")
        _annualRate = State(initialValue: existing?.annualRateText ?? "")
        _maturity = State(initialValue: existing?.maturityDate ?? .now)
        _hasMaturity = State(initialValue: existing?.maturityDate != nil)
        _managesTerms = State(initialValue: existing?.managesTermDeposits ?? false)
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
                    TextField("自定义名称，如 工资卡、微信零钱", text: $name)
                    Picker("类型", selection: $kind) {
                        ForEach(AssetKind.selectable) { Text($0.title).tag($0) }
                    }.disabled(existing != nil)
                    TextField("银行／券商／机构（选填）", text: $institution)
                    if kind == .funds {
                        TextField("账号尾号 4 位（选填）", text: $lastFour).keyboardType(.numberPad)
                        Text("只保存尾号，用于识别截图扣款账户；不需要完整账号。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    TextField("备注（选填）", text: $note, axis: .vertical)
                }
                if kind == .funds {
                    Section {
                        Toggle("管理多笔定期存款", isOn: $managesTerms)
                            .disabled(existing.map { account in deposits.contains { $0.accountID == account.id } } ?? false)
                        Text("开启后，在账户详情逐笔管理定期。本账户总余额应包含活期余额和所有未取出的定期本金。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if kind == .funds && !managesTerms {
                    Section {
                        DisclosureGroup("存款／收益信息（选填）") {
                            TextField("年利率／收益率参考 %", text: $annualRate).keyboardType(.decimalPad)
                            Toggle("记录存款到期日", isOn: $hasMaturity)
                            if hasMaturity {
                                DatePicker("到期日", selection: $maturity, displayedComponents: .date)
                            }
                            Text("用于记录存折或余额宝等账户的参考信息，不自动计入收益。")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let lastUpdate {
                    Section("更新时间") {
                        LabeledContent("上次更新时间", value: lastUpdate.formatted(date: .numeric, time: .shortened))
                        if let previous = existing?.previousUpdatedAt {
                            LabeledContent("前次更新时间", value: previous.formatted(date: .numeric, time: .shortened))
                        }
                        Text("保存后记录本次更新时间，前次时间仍会保留。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if existing == nil {
                    Section(kind == .stocks ? "当前可用现金" : (managesTerms ? "当前总余额（含所有定期本金）" : "当前余额")) {
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
            .alert("保存失败，请重试", isPresented: $failed) { Button("好", role: .cancel) {} }
        }
    }
    private func save() {
        let account = existing ?? AssetAccount(name: name, kind: kind)
        account.managesTermDeposits = managesTerms
        account.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        account.depositStyle = hasMaturity ? "定期" : "活期"
        account.annualRateText = annualRate.isEmpty ? nil : annualRate
        account.maturityDate = hasMaturity ? maturity : nil
        account.institution = institution; account.lastFour = lastFour; account.note = note
        if existing != nil { account.recordUpdate(previousDate: lastUpdate) }
        if existing == nil {
            account.updatedAt = account.createdAt
            account.currencyCode = "CNY"
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
    @Query private var deposits: [TermDeposit]
    private var reserved: Int { deposits.filter { $0.accountID == account.id && $0.isOutstanding }.reduce(0) { $0 + $1.principalInCents } }
    @Query private var snapshots: [AssetBalanceSnapshot]
    private var lastUpdate: Date {
        max(account.updatedAt ?? account.createdAt,
            snapshots.filter { $0.accountID == account.id }.map(\.date).max() ?? account.createdAt)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("上次更新时间", value: lastUpdate.formatted(date: .numeric, time: .shortened))
                }
                Section(account.kind == .stocks ? "当前可用现金 · 人民币" : (account.managesTermDeposits ? "账户总余额（活期＋定期本金）" : "当前账户余额 · 人民币")) {
                    TextField("输入核对后的金额", text: $amount).keyboardType(.decimalPad)
                    TextField("核对说明（选填）", text: $note)
                    Text(account.managesTermDeposits ? "填写活期余额与未取出定期本金之和；不能低于已录入的定期本金。核对不记为收入。" : "此次核对会更新当前余额并保留旧记录，不会记作收入或支出。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.navigationTitle("余额核对").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(AssetMath.cents(amount).map { $0 < reserved } ?? true) }
            }
            .alert("核对失败，请重试", isPresented: $failed) { Button("好", role: .cancel) {} }
        }
    }
    private func save() {
        do {
            let portfolio = try AssetRepository.fetch(context)
            guard let amount = AssetMath.cents(amount), amount >= portfolio.termPrincipal(account) else { throw TermDepositError.insufficient }
            let value = amount + (account.kind == .stocks ? portfolio.stockValue(account) : 0)
            let now = Date()
            account.recordUpdate(at: now, previousDate: portfolio.lastUpdateDate(account))
            context.insert(AssetBalanceSnapshot(accountID: account.id, amountInCents: value, date: now,
                note: note.isEmpty ? "余额核对" : note))
            try context.save(); dismiss()
        } catch { context.rollback(); failed = true }
    }
}
