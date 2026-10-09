import AppIntents
import Foundation
import SwiftData
import Vision


struct PaymentOCR {
    static func recognize(_ data: Data) throws -> (text: String, confidence: Float) {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        request.usesLanguageCorrection = true
        try VNImageRequestHandler(data: data).perform([request])
        let lines = (request.results ?? []).compactMap { observation -> PaymentOCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return PaymentOCRLine(text: candidate.string, confidence: candidate.confidence, bounds: observation.boundingBox)
        }
        guard !lines.isEmpty else { throw ScreenshotError.noText }
        return PaymentOCRText.assemble(lines)
    }
}

enum ScreenshotError: LocalizedError {
    case noText
    var errorDescription: String? { "图片中没有可识别的文字。请在支付成功或账单详情页重试。" }
}

enum ScreenshotCategory: String, AppEnum {
    case food, transport, shopping, housing, entertainment, medical, other
    case salary, bonus, freelance, investment

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "记账分类"
    static var caseDisplayRepresentations: [ScreenshotCategory: DisplayRepresentation] = [
        .food: "餐饮", .transport: "交通", .shopping: "购物", .housing: "住房",
        .entertainment: "娱乐", .medical: "医疗", .other: "其他",
        .salary: "工资", .bonus: "奖金", .freelance: "兼职", .investment: "理财收益"
    ]

    var ledgerName: String {
        switch self {
        case .food: "餐饮"
        case .transport: "交通"
        case .shopping: "购物"
        case .housing: "住房"
        case .entertainment: "娱乐"
        case .medical: "医疗"
        case .other: "其他"
        case .salary: "工资"
        case .bonus: "奖金"
        case .freelance: "兼职"
        case .investment: "理财收益"
        }
    }

    static func options(for payment: RecognizedPayment) -> [ScreenshotCategory] {
        var options: [ScreenshotCategory] = payment.isIncome
            ? [.salary, .bonus, .freelance, .investment, .other]
            : [.food, .transport, .shopping, .housing, .entertainment, .medical, .other]
        if let suggested = options.firstIndex(where: { $0.ledgerName == payment.category }),
           options[suggested] != .other {
            options.insert(options.remove(at: suggested), at: 0)
        }
        return options
    }
}

struct RecordPaymentScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "识别支付截图并记账"
    static var description = IntentDescription("在本机识别支付截图，选择分类后记账；信息不完整时保存为待确认，不计入收支。")
    static var openAppWhenRun = false

    @Parameter(title: "支付截图")
    var screenshot: IntentFile

    @Parameter(title: "分类", description: "留空时，截图识别后弹出分类选择；填写后使用固定分类。")
    var category: ScreenshotCategory?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        var payment = try await PaymentScreenshotRecognizer.recognize(screenshot.data)
        let options = ScreenshotCategory.options(for: payment)
        let selected: ScreenshotCategory
        if let category, options.contains(category) {
            selected = category
        } else {
            let direction = payment.isIncome ? "收入" : "支出"
            let amount = payment.amountInCents.map {
                (Decimal($0) / 100).formatted(.currency(code: "CNY"))
            } ?? "金额待核对"
            let merchant = payment.merchant ?? "商户待核对"
            // Request the system picker before saving; cancellation leaves the ledger unchanged.
            selected = try await $category.requestDisambiguation(
                among: options,
                dialog: "\(direction) \(amount)，\(merchant)。请选择分类。"
            )
        }
        payment.category = selected.ledgerName
        let context = ModelContext(AssetStore.container)
        let outcome = try ScreenshotLedgerService.save(payment, screenshotData: screenshot.data, in: context)
        guard case .saved(let expense) = outcome else {
            return .result(dialog: "这张截图已处理，没有重复记账。")
        }
        if expense.needsConfirmation {
            return .result(dialog: "截图已保存为待确认，暂未计入收支。可稍后在资产流核对。")
        }
        let amount = (Decimal(expense.amountInCents) / 100).formatted(.currency(code: "CNY"))
        if expense.isIncome {
            return .result(dialog: "已记录收入 \(amount)，\(expense.category)。")
        }
        return .result(dialog: "已记录支出 \(amount)，\(expense.category)。")
    }
}

enum PaymentScreenshotRecognizer {
    static func recognize(_ data: Data) async throws -> RecognizedPayment {
        let recognized = try await Task.detached(priority: .userInitiated) {
            try PaymentOCR.recognize(data)
        }.value
        var payment = PaymentParser.parse(recognized.text)
        if recognized.confidence < PaymentOCRText.reviewConfidenceThreshold {
            payment.reasons.append("金额或日期识别可信度偏低")
        }
        return payment
    }
}
