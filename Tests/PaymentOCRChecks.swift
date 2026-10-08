import Foundation
import Vision

@main
struct PaymentOCRChecks {
    static func main() throws {
        let label = PaymentOCRLine(text: "创建时间", confidence: 0.5, bounds: CGRect(x: 0.06, y: 0.58, width: 0.2, height: 0.02))
        let value = PaymentOCRLine(text: "2026-10-08 09:37:21", confidence: 1, bounds: CGRect(x: 0.31, y: 0.58, width: 0.4, height: 0.02))
        let amount = PaymentOCRLine(text: "-10.00", confidence: 1, bounds: CGRect(x: 0.37, y: 0.73, width: 0.2, height: 0.03))
        let footer = PaymentOCRLine(text: "更多", confidence: 0.2, bounds: CGRect(x: 0.45, y: 0.28, width: 0.1, height: 0.02))
        let assembled = PaymentOCRText.assemble([label, footer, value, amount])
        precondition(assembled.text == "-10.00\n创建时间 2026-10-08 09:37:21\n更多")
        precondition(assembled.confidence == 1)
        let uncertainAmount = PaymentOCRLine(text: "-10.00", confidence: 0.3, bounds: amount.bounds)
        precondition(PaymentOCRText.assemble([label, value, uncertainAmount, footer]).confidence < 0.85)
        precondition(PaymentOCRText.assemble([]).text.isEmpty)
        if CommandLine.arguments.count > 1 {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["zh-Hans", "en-US"]
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(url: URL(fileURLWithPath: CommandLine.arguments[1])).perform([request])
            let lines = (request.results ?? []).compactMap { observation -> PaymentOCRLine? in
                guard let candidate = observation.topCandidates(1).first else { return nil }
                return PaymentOCRLine(text: candidate.string, confidence: candidate.confidence, bounds: observation.boundingBox)
            }
            let result = PaymentOCRText.assemble(lines)
            let payment = PaymentParser.parse(result.text, now: Date(timeIntervalSince1970: 1_900_000_000))
            precondition(payment.amountInCents == 1000)
            precondition(payment.date != nil)
            precondition(payment.merchant?.contains("支付宝小荷包") == true)
            precondition(payment.paymentMethod == "招商银行储蓄卡(1373)")
            precondition(payment.reasons.isEmpty && result.confidence >= 0.85)
            print("Provided screenshot: OCR and parsing checks passed")
        }
        print("OCR layout and confidence checks passed")
    }
}
