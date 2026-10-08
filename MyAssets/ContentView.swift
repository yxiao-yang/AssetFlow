import SwiftUI
import SwiftData

@Model
final class Expense {
    var amountInCents: Int
    var category: String
    var note: String
    var date: Date

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
                Section("支出记录") {
                    if expenses.isEmpty {
                        ContentUnavailableView("还没有记录", systemImage: "book.closed",
                            description: Text("点击右上角 +，记下第一笔支出。"))
                    }
                    ForEach(expenses) { expense in
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
                    .onDelete(perform: delete)
                }
            }
            .navigationTitle("我的账本")
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
        for index in offsets { context.delete(expenses[index]) }
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
                }
            }
            .navigationTitle("记一笔支出")
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
        context.insert(Expense(amountInCents: cents, category: category,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines), date: date))
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
