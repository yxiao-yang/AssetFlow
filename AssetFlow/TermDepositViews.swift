import SwiftUI
import SwiftData

struct TermDepositSection: View {
    let account: AssetAccount
    let portfolio: AssetPortfolio
    let hidden: Bool
    @State private var adding = false
    @State private var selected: TermDeposit?
    private var rows: [TermDeposit] {
        portfolio.termDeposits(account).sorted {
            if $0.isOutstanding != $1.isOutstanding { return $0.isOutstanding }
            return $0.maturityDate < $1.maturityDate
        }
    }
    var body: some View {
        Section("存折账户构成") {
            LabeledContent("活期余额", value: assetMoney(portfolio.availableBalance(account), hidden: hidden))
            LabeledContent("定期本金", value: assetMoney(portfolio.termPrincipal(account), hidden: hidden))
            LabeledContent("预计到期利息", value: assetMoney(rows.filter(\.isOutstanding).reduce(0) { $0 + $1.estimatedInterest }, hidden: hidden))
            Text("总资产仅包含活期余额和未取出的定期本金。预计利息按本金 × 年利率 × 实际天数 ÷ 365 估算，未计入资产，以银行实际到账为准。")
                .font(.caption).foregroundStyle(.secondary)
            if portfolio.availableBalance(account) < 0 {
                Text("活期余额为负，请核对账户总余额或定期本金，未取出的本金不可用于日常转账。")
                    .font(.caption).foregroundStyle(.red)
            }
        }
        Section("定期存款 · \(rows.filter(\.isOutstanding).count) 笔未取出") {
            if rows.isEmpty { Text("录入这个存折里的每一笔定期存款").font(.subheadline).foregroundStyle(.secondary) }
            ForEach(rows) { deposit in
                Button { selected = deposit } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Text(deposit.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                            Spacer()
                            Text(assetMoney(deposit.principalInCents, hidden: hidden)).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                        }
                        HStack {
                            Text(deposit.status()).foregroundStyle(deposit.isOutstanding ? LedgerStyle.accent : .secondary)
                            Spacer()
                            Text(hidden ? "利率 •••" : "年利率 " + deposit.annualRateText + "%").foregroundStyle(.secondary)
                        }.font(.caption)
                        Text("存入 " + deposit.openedAt.formatted(date: .numeric, time: .omitted) + " · 到期 " + deposit.maturityDate.formatted(date: .numeric, time: .omitted))
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                }.buttonStyle(.plain)
            }
            Button { adding = true } label: { Label("添加定期存款", systemImage: "plus.circle") }
            Text("到期后仍计入定期本金，实际取出或转存时再更新状态。")
                .font(.caption).foregroundStyle(.secondary)
        }
        .sheet(isPresented: $adding) { TermDepositEditor(account: account) }
        .sheet(item: $selected) { TermDepositEditor(account: account, existing: $0) }
    }
}

private enum TermSettlementMode: String, Identifiable {
    case withdraw, renew
    var id: String { rawValue }
}

struct TermDepositEditor: View {
    let account: AssetAccount
    private let existing: TermDeposit?
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var principal: String
    @State private var rate: String
    @State private var openedAt: Date
    @State private var maturity: Date
    @State private var note: String
    @State private var error: String?
    @State private var removing = false
    @State private var settlement: TermSettlementMode?
    private var editable: Bool { existing?.isOutstanding ?? true }
    private var valid: Bool {
        AssetMath.cents(principal, allowZero: false) != nil && TermDepositMath.rate(rate) != nil &&
        TermDepositMath.days(start: openedAt, end: maturity) > 0
    }
    init(account: AssetAccount, existing: TermDeposit? = nil) {
        self.account = account; self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _principal = State(initialValue: existing.map { NSDecimalNumber(decimal: Decimal($0.principalInCents) / 100).stringValue } ?? "")
        _rate = State(initialValue: existing?.annualRateText ?? "")
        _openedAt = State(initialValue: existing?.openedAt ?? Calendar.current.startOfDay(for: .now))
        _maturity = State(initialValue: existing?.maturityDate ?? Calendar.current.date(byAdding: .year, value: 1, to: .now)!)
        _note = State(initialValue: existing?.note ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("定期明细 · 人民币") {
                    TextField("名称，如 第一笔三年定期（选填）", text: $name)
                    TextField("本金", text: $principal).keyboardType(.decimalPad)
                    TextField("年利率 %，如 1.5", text: $rate).keyboardType(.decimalPad)
                    DatePicker("存入日", selection: $openedAt, in: ...Date(), displayedComponents: .date)
                    DatePicker("到期日", selection: $maturity, displayedComponents: .date)
                    TextField("备注（选填）", text: $note, axis: .vertical)
                }.disabled(!editable)
                if valid, let cents = AssetMath.cents(principal), let interest = TermDepositMath.estimatedInterest(principal: cents, rate: rate, start: openedAt, end: maturity) {
                    Section("到期估算") {
                        LabeledContent("期限", value: "\(TermDepositMath.days(start: openedAt, end: maturity)) 天")
                        LabeledContent("预计利息", value: assetMoney(interest))
                        Text("按实际天数 ÷ 365 估算，不自动记为收入。实际利息以银行结算为准。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let existing {
                    Section("状态") {
                        LabeledContent("存款状态", value: existing.status())
                        if let closedAt = existing.closedAt { LabeledContent("结清时间", value: closedAt.formatted(date: .numeric, time: .shortened)) }
                        if let interest = existing.settledInterestInCents { LabeledContent("实际到账利息", value: assetMoney(interest)) }
                    }
                    if editable {
                        Section {
                            Button("取出这笔存款") { settlement = .withdraw }
                            Button("转存为本账户新定期") { settlement = .renew }
                            Button("删除录入记录", role: .destructive) { removing = true }
                        }
                    }
                }
                Section {
                    Text("录入已包含在账户总余额中的定期本金，仅拆分活期与定期，不增加资产。如总余额未包含这笔钱，请先核对账户总余额。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(existing == nil ? "添加定期存款" : "定期存款详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                if editable { ToolbarItem(placement: .confirmationAction) { Button("保存", action: save).disabled(!valid) } }
            }
            .confirmationDialog("删除这笔录入记录？", isPresented: $removing, titleVisibility: .visible) {
                Button("删除记录", role: .destructive) {
                    guard let existing else { return }
                    do { try TermDepositRepository.removeRecord(existing, context: context); dismiss() }
                    catch { self.error = error.localizedDescription }
                }
            } message: { Text("仅删除定期明细，不扣减账户总额，本金重新归入活期余额。如已实际取出，请使用取出功能。") }
            .sheet(item: $settlement) { mode in
                if let existing { TermDepositSettlement(deposit: existing, account: account, renewing: mode == .renew, completed: { dismiss() }) }
            }
            .alert("未能保存", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard let principal = AssetMath.cents(principal, allowZero: false) else { return }
        do {
            try TermDepositRepository.save(account: account, existing: existing, name: name, principal: principal,
                rate: rate, openedAt: openedAt, maturity: maturity, note: note, context: context)
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct TermDepositSettlement: View {
    let deposit: TermDeposit
    let account: AssetAccount
    let renewing: Bool
    let completed: () -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [AssetAccount]
    @State private var destinationID: UUID
    @State private var interest = "0"
    @State private var principal: String
    @State private var rate = ""
    @State private var maturity = Calendar.current.date(byAdding: .year, value: 1, to: .now)!
    @State private var error: String?
    private var eligible: [AssetAccount] { accounts.filter { $0.archivedAt == nil && $0.currencyCode == "CNY" && $0.kind != .stocks } }
    private var valid: Bool {
        AssetMath.cents(interest) != nil && (renewing ?
            (AssetMath.cents(principal, allowZero: false) != nil && TermDepositMath.rate(rate) != nil && TermDepositMath.days(start: .now, end: maturity) > 0) :
            eligible.contains { $0.id == destinationID })
    }
    init(deposit: TermDeposit, account: AssetAccount, renewing: Bool, completed: @escaping () -> Void) {
        self.deposit = deposit; self.account = account; self.renewing = renewing; self.completed = completed
        _destinationID = State(initialValue: account.id)
        _principal = State(initialValue: NSDecimalNumber(decimal: Decimal(deposit.principalInCents) / 100).stringValue)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("本次结清") {
                    LabeledContent("原本金", value: assetMoney(deposit.principalInCents))
                    TextField("实际到账利息（可填 0）", text: $interest).keyboardType(.decimalPad)
                    Text("只填写银行实际结算的利息，提前取出时也以实际到账为准。本金不记为收入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if renewing {
                    Section("新定期 · 本账户") {
                        TextField("新本金，可包含实际利息", text: $principal).keyboardType(.decimalPad)
                        TextField("新年利率 %", text: $rate).keyboardType(.decimalPad)
                        LabeledContent("存入日", value: Date.now.formatted(date: .numeric, time: .omitted))
                        DatePicker("新到期日", selection: $maturity, displayedComponents: .date)
                        Text("原记录保留并标为已转存，新本金从本账户活期余额中拆分。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Section("本金与利息去向") {
                        Picker("转入账户", selection: $destinationID) {
                            ForEach(eligible) { Text($0.id == account.id ? "本账户活期余额" : $0.name).tag($0.id) }
                        }
                        Text("整笔取出；转入其他账户时，本金记为转账，利息记为理财收入。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(renewing ? "转存定期" : "取出定期").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("确认", action: save).disabled(!valid) }
            }
            .alert("操作未完成", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("好", role: .cancel) { error = nil }
            } message: { Text(error ?? "") }
        }
    }
    private func save() {
        guard let interest = AssetMath.cents(interest) else { return }
        do {
            if renewing, let principal = AssetMath.cents(principal, allowZero: false) {
                try TermDepositRepository.renew(deposit, principal: principal, rate: rate, maturity: maturity,
                    interest: interest, context: context)
            } else if let destination = eligible.first(where: { $0.id == destinationID }) {
                try TermDepositRepository.withdraw(deposit, to: destination, interest: interest, context: context)
            } else { throw TermDepositError.missing }
            dismiss(); completed()
        } catch { self.error = error.localizedDescription }
    }
}
