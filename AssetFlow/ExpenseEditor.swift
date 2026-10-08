import SwiftUI
import SwiftData

struct ExpenseEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var isIncome = false
    @State private var category = "餐饮"
    @State private var note = ""
    @State private var date = Date()
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool
    @Query(sort: \AssetAccount.createdAt) private var accounts: [AssetAccount]
    @State private var accountID: UUID?
    private var eligibleAccounts: [AssetAccount] {
        accounts.filter { $0.archivedAt == nil && $0.currencyCode == "CNY" && $0.kind != .stocks }
    }
    private let existing: Expense?
    private let onSaved: (Expense) -> Void

    init(existing: Expense? = nil, onSaved: @escaping (Expense) -> Void = { _ in }) {
        self.existing = existing
        self.onSaved = onSaved
        _accountID = State(initialValue: existing?.accountID)
        _isIncome = State(initialValue: existing?.isIncome ?? false)
        _amount = State(initialValue: existing.map {
            $0.amountInCents > 0 ? NSDecimalNumber(decimal: Decimal($0.amountInCents) / 100).stringValue : ""
        } ?? "")
        _category = State(initialValue: existing?.category ?? "餐饮")
        _note = State(initialValue: existing?.note ?? "")
        _date = State(initialValue: existing?.date ?? .now)
    }

    private var categories: [String] {
        isIncome ? ["工资", "奖金", "兼职", "理财收益", "其他"] : ["餐饮", "交通", "购物", "住房", "娱乐", "医疗", "其他"]
    }

    private var cents: Int? {
        let text = amount.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "。", with: ".")
        guard text.range(of: "^[0-9]+([.][0-9]{1,2})?$", options: .regularExpression) != nil,
              let value = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              value > 0, value <= 999_999_999 else { return nil }
        return NSDecimalNumber(decimal: value * 100).intValue
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("类型", selection: $isIncome) {
                        Text("支出").tag(false)
                        Text("收入").tag(true)
                    }.pickerStyle(.segmented)
                    .onChange(of: isIncome) { _, _ in category = categories[0] }
                }
                Section("金额（人民币）") {
                    TextField("例如 28.50", text: $amount)
                        .keyboardType(.decimalPad)
                        .focused($amountFocused)
                    if !amount.isEmpty && cents == nil {
                        Text("请输入大于 0 的金额，最多两位小数，上限 999,999,999 元。")
                            .font(.caption).foregroundStyle(.red)
                    }
                }
                Section("详情") {
                    Picker("分类", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0) }
                    }
                    Picker("关联资产账户", selection: $accountID) {
                        Text("不关联账户").tag(nil as UUID?)
                        ForEach(eligibleAccounts) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Text("关联人民币账户后更新余额；早于最近余额核对的记录不会再重复扣款。")
                        .font(.caption).foregroundStyle(.secondary)
                    DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("备注（选填）", text: $note)
                    if let existing, existing.needsConfirmation {
                        Text(existing.reviewReason ?? "请核对")
                            .font(.footnote).foregroundStyle(.orange)
                        Text("请核对金额、时间和收支类型。自己的账户间转账请在资产页记录；退款、充值和还款请勿直接确认为普通消费。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? "记一笔" : "核对记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save).disabled(cents == nil)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") { amountFocused = false }
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard let cents else { return }
        let expense = existing ?? Expense(amountInCents: cents, category: category, note: "", date: date)
        expense.accountID = accountID
        expense.isIncome = isIncome
        expense.amountInCents = cents
        expense.category = category
        expense.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.date = date
        expense.needsConfirmation = false
        expense.dateIsEstimated = false
        if existing == nil { context.insert(expense) }
        do {
            try context.save()
            onSaved(expense)
            dismiss()
        } catch {
            context.rollback()
            errorMessage = "记录未能保存，请重试。"
        }
    }
}


struct ExpenseDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [AssetAccount]
    let expense: Expense
    @State private var editing = false
    @State private var deleting = false
    @State private var deletionError = false

    var body: some View {
        List {
            Section("记录") {
                if let account = accounts.first(where: { $0.id == expense.accountID }) {
                    LabeledContent("资产账户", value: account.name)
                }
                LabeledContent("类型", value: expense.isIncome ? "收入" : "支出")
                LabeledContent("金额", value: expense.amountInCents > 0 ? money(expense.amountInCents) : "未识别")
                LabeledContent("分类（可修改）", value: expense.category)
                LabeledContent("备注", value: expense.note)
                LabeledContent("时间", value: expense.date.formatted(date: .numeric, time: .shortened))
                if expense.dateIsEstimated { Text("时间暂用采集时间，请核对原始账单。") .font(.footnote).foregroundStyle(.orange) }
                if expense.needsConfirmation {
                    Text(expense.reviewReason ?? "待确认").foregroundStyle(.orange)
                }
            }
            if expense.rawText != nil {
                Section("来源信息") {
                    LabeledContent("商户", value: expense.merchant ?? "未识别")
                    LabeledContent("支付渠道", value: expense.paymentChannel ?? "未识别")
                    LabeledContent("扣款方式", value: expense.paymentMethod ?? "未识别")
                    LabeledContent("交易单号", value: expense.transactionID ?? "未识别")
                    Text("明确匹配的账户会自动关联；也可在编辑记录中手动选择。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("原始截图") {
                    if let data = expense.screenshotData, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                    }
                }
                Section("识别原文") {
                    Text(expense.rawText ?? "").font(.footnote).textSelection(.enabled)
                }
            }
            Section {
                Button(expense.needsConfirmation ? "核对并入账" : "编辑记录") { editing = true }
                Button("删除记录", role: .destructive) { deleting = true }
            }
        }
        .navigationTitle(expense.needsConfirmation ? "待确认" : "账单详情")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $editing) { ExpenseEntryView(existing: expense) }
        .confirmationDialog("删除此记录及其截图？", isPresented: $deleting, titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                context.delete(expense)
                do { try context.save(); dismiss() }
                catch { context.rollback(); deletionError = true }
            }
        }
        .alert("删除失败，请重试", isPresented: $deletionError) {
            Button("好", role: .cancel) {}
        }
    }
}
