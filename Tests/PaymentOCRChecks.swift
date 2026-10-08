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
        precondition(PaymentOCRText.assemble([label, value, uncertainAmount, footer]).confidence < PaymentOCRText.reviewConfidenceThreshold)
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
            if CommandLine.arguments.dropFirst(2).contains("--yuebao-income") {
                precondition(payment.amountInCents == 16 && payment.isIncome)
                precondition(payment.merchant == "余额宝" && payment.category == "理财收益")
                precondition(payment.paymentMethod == "余额宝" && payment.paymentChannel == "支付宝")
            } else if CommandLine.arguments.dropFirst(2).contains("--wechat") {
                precondition(payment.amountInCents == 27500 && !payment.isIncome)
                precondition(payment.merchant == "美团" && payment.category == "娱乐")
                precondition(payment.paymentMethod == "零钱" && payment.paymentChannel == "微信")
                precondition(payment.productDescription?.contains("SPA") == true)
            } else if CommandLine.arguments.dropFirst(2).contains("--shop") {
                precondition(payment.amountInCents == 420 && !payment.isIncome)
                precondition(payment.merchant == "好想来零食乐园" && payment.category == "餐饮")
                precondition(payment.paymentMethod == "招商银行信用卡(5550)")
            } else if CommandLine.arguments.dropFirst(2).contains("--noodle") {
                precondition(payment.amountInCents == 1500 && !payment.isIncome)
                precondition(payment.merchant == "老高亚笛板面" && payment.category == "餐饮")
                precondition(payment.paymentMethod == "招商银行储蓄卡(1373)")
            } else {
                precondition(payment.amountInCents == 1000 && !payment.isIncome)
                precondition(payment.merchant?.contains("支付宝小荷包") == true)
                precondition(payment.paymentMethod == "招商银行储蓄卡(1373)")
            }
            precondition(payment.date != nil)
            precondition(payment.reasons.isEmpty && result.confidence >= PaymentOCRText.reviewConfidenceThreshold)
            print("Provided screenshot: OCR and parsing checks passed")
        }
        print("OCR layout and confidence checks passed")
    }
}
