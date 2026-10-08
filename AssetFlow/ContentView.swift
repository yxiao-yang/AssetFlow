import SwiftUI
import SwiftData

@Model
final class Expense {
    var amountInCents: Int
    var category: String
    var note: String
    var date: Date
    var merchant: String?
    var paymentChannel: String?
    var paymentMethod: String?
    var transactionID: String?
    var rawText: String?
    var screenshotHash: String?
    @Attribute(.externalStorage) var screenshotData: Data?
    var needsConfirmation: Bool = false
    var reviewReason: String?
    var dateIsEstimated: Bool = false

    init(amountInCents: Int, category: String, note: String, date: Date) {
        self.amountInCents = amountInCents
        self.category = category
        self.note = note
        self.date = date
    }
}

private func currency(_ cents: Int) -> String {
    (Decimal(cents) / 100).formatted(.currency(code: "CNY"))
}

struct ContentView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]
    @State private var showingEntry = false
    @State private var errorMessage: String?

    private var monthlyTotal: Int {
        expenses.filter {
            !$0.needsConfirmation &&
            Calendar.current.isDate($0.date, equalTo: .now, toGranularity: .month)
        }.reduce(0) { $0 + $1.amountInCents }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("本月支出").foregroundStyle(.secondary)
                        Text(currency(monthlyTotal))
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        Text("从每一笔记录开始，了解自己的花费。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 12)
                }
                if expenses.contains(where: \.needsConfirmation) {
                    Section("待确认 · 暂不计入支出") {
                        ForEach(expenses.filter(\.needsConfirmation)) { expense in
                            NavigationLink {
                                ExpenseDetailView(expense: expense)
                            } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(expense.merchant ?? "待核对的支付截图")
                                    Text(expense.reviewReason ?? "请核对识别结果")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("支出记录") {
                    if expenses.isEmpty {
                        ContentUnavailableView("还没有记录", systemImage: "book.closed",
                            description: Text("点击右上角 +，记下第一笔支出。"))
                    }
                    ForEach(expenses.filter { !$0.needsConfirmation }) { expense in
                        NavigationLink {
                            ExpenseDetailView(expense: expense)
                        } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(expense.category).font(.headline)
                                if !expense.note.isEmpty {
                                    Text(expense.note).font(.subheadline)
                                }
                                Text(expense.date, format: .dateTime.year().month().day())
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("−" + currency(expense.amountInCents))
                                .fontWeight(.semibold)
                        }
                        .padding(.vertical, 4)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("资产流")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("记一笔", systemImage: "plus") { showingEntry = true }
                }
            }
            .sheet(isPresented: $showingEntry) { ExpenseEntryView() }
            .alert("删除失败", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func delete(at offsets: IndexSet) {
        let recorded = expenses.filter { !$0.needsConfirmation }
        for index in offsets { context.delete(recorded[index]) }
        do { try context.save() }
        catch {
            context.rollback()
            errorMessage = "未能保存删除操作，请重试。"
        }
    }
}

private struct ExpenseEntryView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var amount = ""
    @State private var category = "餐饮"
    @State private var note = ""
    @State private var date = Date()
    @State private var errorMessage: String?
    @FocusState private var amountFocused: Bool
    private let existing: Expense?

    init(existing: Expense? = nil) {
        self.existing = existing
        _amount = State(initialValue: existing.map {
            $0.amountInCents > 0 ? NSDecimalNumber(decimal: Decimal($0.amountInCents) / 100).stringValue : ""
        } ?? "")
        _category = State(initialValue: existing?.category ?? "餐饮")
        _note = State(initialValue: existing?.note ?? "")
        _date = State(initialValue: existing?.date ?? .now)
    }

    private let categories = ["餐饮", "交通", "购物", "住房", "娱乐", "医疗", "其他"]

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
                    DatePicker("日期", selection: $date, in: ...Date(), displayedComponents: .date)
                    TextField("备注（选填）", text: $note)
                    if let existing, existing.needsConfirmation {
                        Text(existing.reviewReason ?? "请核对")
                            .font(.footnote).foregroundStyle(.orange)
                        Text("保存表示你已确认这是一笔人民币消费支出。退款、转账、充值和还款请勿在此入账。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(existing == nil ? "记一笔支出" : "核对支出")
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
        expense.amountInCents = cents
        expense.category = category
        expense.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        expense.date = date
        expense.needsConfirmation = false
        expense.dateIsEstimated = false
        if existing == nil { context.insert(expense) }
        do {
            try context.save()
            dismiss()
        } catch {
            context.rollback()
            errorMessage = "记录未能保存，请重试。"
        }
    }
}

#Preview {
    ContentView().modelContainer(for: Expense.self, inMemory: true)
}


private struct ExpenseDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let expense: Expense
    @State private var editing = false
    @State private var deleting = false
    @State private var deletionError = false

    var body: some View {
        List {
            Section("记录") {
                LabeledContent("金额", value: expense.amountInCents > 0 ? currency(expense.amountInCents) : "未识别")
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
                    Text("扣款方式为截图原文，尚未关联资产账户。")
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
                Button(expense.needsConfirmation ? "核对并记为支出" : "编辑记录") { editing = true }
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
