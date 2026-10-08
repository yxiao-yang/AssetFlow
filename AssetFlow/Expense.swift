import Foundation
import SwiftData

@Model
final class Expense {
    var isIncome: Bool = false
    var amountInCents: Int
    var category: String
    var note: String
    var date: Date
    var accountID: UUID?
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

