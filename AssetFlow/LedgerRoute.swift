import SwiftData

/// Navigation stores stable identifiers rather than observable model instances.
enum LedgerRoute: Hashable {
    case pending
    case record(PersistentIdentifier)
}
