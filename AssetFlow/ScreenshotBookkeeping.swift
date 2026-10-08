import AppIntents
import CryptoKit
import Foundation
import SwiftData
import Vision

@MainActor
enum AssetStore {
    static let container: ModelContainer = {
        do {
            #if DEBUG
            if CommandLine.arguments.contains("--demo-ledger") {
                let container = try ModelContainer(for: Expense.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
                LedgerDemo.seed(container.mainContext)
                return container
            }
            #endif
            return try ModelContainer(for: Expense.self)
        }
        catch { fatalError("无法打开本地账本：\(error.localizedDescription)") }
    }()
}

struct PaymentOCR {
    static func recognize(_ data: Data) throws -> (text: String, confidence: Float) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: data).perform([request])
        let candidates = (request.results ?? []).compactMap { $0.topCandidates(1).first }
        guard !candidates.isEmpty else { throw ScreenshotError.noText }
        return (candidates.map(\.string).joined(separator: "\n"), candidates.map(\.confidence).min() ?? 0)
    }
}

enum ScreenshotError: LocalizedError {
    case noText
    var errorDescription: String? { "图片中没有可识别的文字。请在支付成功或账单详情页重试。" }
}

struct RecordPaymentScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "识别支付截图并记账"
    static var description = IntentDescription("在本机识别支付截图；信息不完整时保存为待确认，不计入支出。")
    static var openAppWhenRun = false

    @Parameter(title: "支付截图")
    var screenshot: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let data = screenshot.data
        let recognized = try await Task.detached(priority: .userInitiated) {
            try PaymentOCR.recognize(data)
        }.value
        var payment = PaymentParser.parse(recognized.text)
        if recognized.confidence < 0.85 { payment.reasons.append("部分文字识别可信度偏低") }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let context = ModelContext(AssetStore.container)
        let existing = try context.fetch(FetchDescriptor<Expense>())
        if existing.contains(where: { $0.screenshotHash == hash }) {
            return .result(dialog: "这张截图已处理，没有重复记账。")
        }
        if let id = payment.transactionID, existing.contains(where: {
            $0.transactionID == id && $0.paymentChannel == payment.paymentChannel
        }) {
            // Keep both source images available for review; never silently overwrite an earlier entry.
            payment.reasons.append("交易单号与已有记录相同，请核对重复记录")
        } else if existing.contains(where: {
            $0.merchant == payment.merchant && payment.merchant != nil &&
            $0.amountInCents == payment.amountInCents &&
            abs($0.date.timeIntervalSince(payment.date ?? .now)) < 120
        }) {
            payment.reasons.append("附近时间有同商户同金额记录，可能重复")
        }
        let expense = Expense(amountInCents: payment.amountInCents ?? 0,
            category: payment.category, note: payment.merchant ?? "截图记账", date: payment.date ?? .now)
        expense.merchant = payment.merchant
        expense.paymentChannel = payment.paymentChannel
        expense.paymentMethod = payment.paymentMethod
        expense.transactionID = payment.transactionID
        expense.rawText = payment.rawText
        expense.screenshotHash = hash
        expense.screenshotData = data
        expense.needsConfirmation = !payment.reasons.isEmpty
        expense.reviewReason = payment.reasons.joined(separator: "；")
        expense.dateIsEstimated = payment.date == nil
        context.insert(expense)
        try context.save()
        if expense.needsConfirmation {
            return .result(dialog: "截图已保存为待确认，暂未计入支出。可稍后在资产流核对。")
        }
        let amount = (Decimal(expense.amountInCents) / 100).formatted(.currency(code: "CNY"))
        return .result(dialog: "已记录支出 \(amount)，\(expense.category)。")
    }
}
