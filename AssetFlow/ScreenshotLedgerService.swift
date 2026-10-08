import Foundation
import SwiftData
import CryptoKit

enum ScreenshotRecordOutcome {
    case saved(Expense)
    case duplicate
}

enum ScreenshotRecordError: LocalizedError {
    case missing
    var errorDescription: String? { "原记录已不存在，请返回明细页检查。" }
}

@MainActor
enum ScreenshotLedgerService {
    static func save(_ payment: RecognizedPayment, screenshotData data: Data,
                     in context: ModelContext, existingRecord: Expense? = nil, now: Date = .now) throws -> ScreenshotRecordOutcome {
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let records = try context.fetch(FetchDescriptor<Expense>())
        if let existingRecord, !records.contains(where: { $0 === existingRecord }) { throw ScreenshotRecordError.missing }
        let previous = existingRecord ?? records.first { $0.screenshotHash == hash }
        if let previous, !previous.needsConfirmation { return .duplicate }
        var payment = payment
        let others = records.filter { $0 !== previous }
        if let id = payment.transactionID, others.contains(where: {
            $0.transactionID == id && $0.paymentChannel == payment.paymentChannel
        }) {
            payment.reasons.append("交易单号与已有记录相同，请核对重复记录")
        } else if others.contains(where: {
            $0.merchant == payment.merchant && payment.merchant != nil &&
            $0.amountInCents == payment.amountInCents && $0.isIncome == payment.isIncome &&
            abs($0.date.timeIntervalSince(payment.date ?? now)) < 120
        }) {
            payment.reasons.append("附近时间有同商户同金额记录，可能重复")
        }
        let accounts = try context.fetch(FetchDescriptor<AssetAccount>())
        let expense = previous ?? Expense(amountInCents: payment.amountInCents ?? 0,
            category: payment.category, note: "", date: payment.date ?? now)
        expense.isIncome = payment.isIncome
        expense.amountInCents = payment.amountInCents ?? 0
        expense.category = payment.category
        expense.note = payment.productDescription ?? payment.merchant ?? "截图记账"
        expense.date = payment.date ?? now
        expense.accountID = AssetRepository.matchingAccount(method: payment.paymentMethod, in: accounts)?.id ?? previous?.accountID
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
        if previous == nil { context.insert(expense) }
        do { try context.save() } catch { context.rollback(); throw error }
        return .saved(expense)
    }
}
