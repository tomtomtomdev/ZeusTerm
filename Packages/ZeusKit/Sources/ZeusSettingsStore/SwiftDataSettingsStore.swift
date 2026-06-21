import Foundation
import SwiftData
import ZeusDomain

/// SwiftData persistence for one settings record (the stack's "SwiftData = settings" choice,
/// CLAUDE.md). `ZeusSettings` is stored as an encoded payload in a single keyed row rather than
/// a column-per-field: settings is a singleton config blob with no query needs, and an opaque
/// payload means the SwiftData schema never has to migrate every time `ZeusSettings` grows a
/// field. The `@Model` is `internal` so the SwiftData type can't leak past this adapter.
@Model
final class SettingsRecord {
    /// Singleton key — there is only ever one settings row.
    @Attribute(.unique) var key: String
    /// JSON-encoded `ZeusSettings`.
    var payload: Data

    init(key: String, payload: Data) {
        self.key = key
        self.payload = payload
    }
}

/// Implements the domain's `SettingsStoring` port on top of SwiftData. A `ModelContainer` is
/// `Sendable`, so this `final class` with only immutable state is safely `Sendable`; each call
/// makes its own short-lived `ModelContext` (never escaping the call) to stay off any one actor.
public final class SwiftDataSettingsStore: SettingsStoring {
    private let container: ModelContainer
    private static let singletonKey = "default"

    /// - Parameter inMemory: when true, persists nowhere (used by tests); otherwise SwiftData
    ///   picks its default on-disk store. The app uses `init(url:)` to pin the file location.
    public init(inMemory: Bool = false) throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: SettingsRecord.self, configurations: config)
    }

    /// Persists to the SwiftData store at `url` (created if absent). The composition root pins
    /// this under Application Support alongside the scan index.
    public init(url: URL) throws {
        let config = ModelConfiguration(url: url)
        container = try ModelContainer(for: SettingsRecord.self, configurations: config)
    }

    public func load() throws -> ZeusSettings {
        let context = ModelContext(container)
        guard let record = try fetchRecord(in: context) else { return ZeusSettings() }
        return try JSONDecoder().decode(ZeusSettings.self, from: record.payload)
    }

    public func save(_ settings: ZeusSettings) throws {
        let context = ModelContext(container)
        let payload = try JSONEncoder().encode(settings)
        if let record = try fetchRecord(in: context) {
            record.payload = payload   // update the single existing row
        } else {
            context.insert(SettingsRecord(key: Self.singletonKey, payload: payload))
        }
        try context.save()
    }

    private func fetchRecord(in context: ModelContext) throws -> SettingsRecord? {
        let key = Self.singletonKey
        var descriptor = FetchDescriptor<SettingsRecord>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
