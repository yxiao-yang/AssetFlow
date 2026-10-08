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

struct RecordPaymentScreenshotIntent: AppIntent {
    static var title: LocalizedStringResource = "识别支付截图并记账"
    static var description = IntentDescription("在本机识别支付截图；信息不完整时保存为待确认，不计入支出。")
    static var openAppWhenRun = false

    @Parameter(title: "支付截图")
    var screenshot: IntentFile

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let payment = try await PaymentScreenshotRecognizer.recognize(screenshot.data)
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
