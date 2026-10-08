import Foundation
import SwiftData

enum TermDepositError: LocalizedError {
    case invalid, insufficient, closed, missing
    var errorDescription: String? {
        switch self {
        case .invalid: "请检查本金、利率和日期；到期日须晚于存入日。"
        case .insufficient: "定期本金超过可拆分余额，请先核对账户总余额（活期＋定期本金）。"
        case .closed: "这笔存款已经结清，不能重复取出或转存。"
        case .missing: "账户已不可用，请返回账户列表检查。"
        }
    }
}

@MainActor
enum TermDepositRepository {
    static func save(account: AssetAccount, existing: TermDeposit? = nil, name: String, principal: Int,
                     rate: String, openedAt: Date, maturity: Date, note: String,
                     context: ModelContext, now: Date = .now) throws {
        do {
            let portfolio = try AssetRepository.fetch(context)
            try validate(account, in: portfolio)
            guard principal > 0, principal <= 99_999_999_900, TermDepositMath.rate(rate) != nil,
                  TermDepositMath.days(start: openedAt, end: maturity) > 0,
                  Calendar.current.startOfDay(for: openedAt) <= Calendar.current.startOfDay(for: now) else { throw TermDepositError.invalid }
            if let existing {
                guard portfolio.deposits.contains(where: { $0 === existing }), existing.accountID == account.id else { throw TermDepositError.missing }
                guard existing.isOutstanding else { throw TermDepositError.closed }
            }
            guard principal <= portfolio.availableBalance(account) + (existing?.principalInCents ?? 0) else { throw TermDepositError.insufficient }
            let deposit = existing ?? TermDeposit(accountID: account.id, name: name, principalInCents: principal,
                annualRateText: rate, openedAt: openedAt, maturityDate: maturity, note: note, createdAt: now)
            deposit.name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "定期存款" : name.trimmingCharacters(in: .whitespacesAndNewlines)
            deposit.principalInCents = principal; deposit.annualRateText = rate
            deposit.openedAt = openedAt; deposit.maturityDate = maturity; deposit.note = note; deposit.updatedAt = now
            if existing == nil { context.insert(deposit) }
            account.recordUpdate(at: now, previousDate: portfolio.lastUpdateDate(account))
            try context.save()
        } catch { context.rollback(); throw error }
    }

    static func withdraw(_ deposit: TermDeposit, to destination: AssetAccount, interest: Int,
                         context: ModelContext, now: Date = .now) throws {
        do {
            let portfolio = try AssetRepository.fetch(context)
            let source = try sourceAccount(deposit, portfolio: portfolio)
            guard portfolio.activeAccounts.contains(where: { $0 === destination }) else { throw TermDepositError.missing }
            guard interest >= 0, interest <= 99_999_999_900 else { throw TermDepositError.invalid }
            // The principal was already counted as an asset; only the actual interest is new income.
            if source.id != destination.id {
                context.insert(AssetTransfer(fromID: source.id, toID: destination.id,
                    amountInCents: deposit.principalInCents, receivedInCents: deposit.principalInCents,
                    date: now, note: "定期取出本金 · " + deposit.name))
                destination.recordUpdate(at: now, previousDate: portfolio.lastUpdateDate(destination))
            }
            recordInterest(interest, account: destination, deposit: deposit, context: context, now: now)
            deposit.closedAt = now; deposit.closureKind = "withdrawn"
            deposit.settledInterestInCents = interest; deposit.updatedAt = now
            source.recordUpdate(at: now, previousDate: portfolio.lastUpdateDate(source))
            try context.save()
        } catch { context.rollback(); throw error }
    }

    static func renew(_ deposit: TermDeposit, principal: Int, rate: String, maturity: Date,
                      interest: Int, context: ModelContext, now: Date = .now) throws {
        do {
            let portfolio = try AssetRepository.fetch(context)
            let source = try sourceAccount(deposit, portfolio: portfolio)
            guard principal > 0, principal <= 99_999_999_900, interest >= 0, interest <= 99_999_999_900,
                  TermDepositMath.rate(rate) != nil, TermDepositMath.days(start: now, end: maturity) > 0 else { throw TermDepositError.invalid }
            guard principal <= portfolio.availableBalance(source) + deposit.principalInCents + interest else { throw TermDepositError.insufficient }
            recordInterest(interest, account: source, deposit: deposit, context: context, now: now)
            deposit.closedAt = now; deposit.closureKind = "renewed"
            deposit.settledInterestInCents = interest; deposit.updatedAt = now
            let replacement = TermDeposit(accountID: source.id, name: deposit.name + " · 转存",
                principalInCents: principal, annualRateText: rate, openedAt: Calendar.current.startOfDay(for: now),
                maturityDate: maturity, note: deposit.note, createdAt: now)
            replacement.originDepositID = deposit.id
            context.insert(replacement)
            source.recordUpdate(at: now, previousDate: portfolio.lastUpdateDate(source))
            try context.save()
        } catch { context.rollback(); throw error }
    }

    static func removeRecord(_ deposit: TermDeposit, context: ModelContext, now: Date = .now) throws {
        do {
            let portfolio = try AssetRepository.fetch(context)
            guard portfolio.deposits.contains(where: { $0 === deposit }),
                  let source = portfolio.activeAccounts.first(where: { $0.id == deposit.accountID }) else { throw TermDepositError.missing }
            try validate(source, in: portfolio)
            guard deposit.isOutstanding else { throw TermDepositError.closed }
            context.delete(deposit)
            source.recordUpdate(at: now, previousDate: portfolio.lastUpdateDate(source))
            try context.save()
        } catch { context.rollback(); throw error }
    }

    private static func validate(_ account: AssetAccount, in portfolio: AssetPortfolio) throws {
        guard portfolio.activeAccounts.contains(where: { $0 === account }), account.kind.category == .funds,
              account.managesTermDeposits else { throw TermDepositError.missing }
    }
    private static func sourceAccount(_ deposit: TermDeposit, portfolio: AssetPortfolio) throws -> AssetAccount {
        guard portfolio.deposits.contains(where: { $0 === deposit }),
              let account = portfolio.activeAccounts.first(where: { $0.id == deposit.accountID }) else { throw TermDepositError.missing }
        try validate(account, in: portfolio)
        guard deposit.isOutstanding else { throw TermDepositError.closed }
        guard portfolio.balance(account) >= portfolio.termPrincipal(account) else { throw TermDepositError.insufficient }
        return account
    }
    private static func recordInterest(_ interest: Int, account: AssetAccount, deposit: TermDeposit,
                                       context: ModelContext, now: Date) {
        guard interest > 0 else { return }
        let expense = Expense(amountInCents: interest, category: "理财收益", note: "定期实际利息 · " + deposit.name, date: now)
        expense.isIncome = true; expense.accountID = account.id
        context.insert(expense)
    }
}
