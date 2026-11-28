import CoreData
import Foundation

/// Watch later (Sprint 4, Alex; mirrored on iOS · local storage). An ordered
/// queue of shorts to watch later, kept only on the phone in Core Data, so it
/// works the same with or without a connection.
nonisolated struct WatchLaterEntry: Equatable, Sendable, Identifiable {
    let videoID: UUID
    let title: String
    let creator: String
    let addedAt: Date
    /// 0 is the top of the queue.
    var position: Int
    /// Set when the short was opened from the queue.
    var watchedAt: Date?

    var id: UUID { videoID }
    var isWatched: Bool { watchedAt != nil }

    func hoursInQueue(at date: Date) -> Double {
        (date.timeIntervalSince(addedAt) / 360).rounded() / 10
    }
}

nonisolated protocol WatchLaterStoring: Sendable {
    /// Unwatched first in queue order, then watched ones.
    func entries() async -> [WatchLaterEntry]
    func contains(_ videoID: UUID) async -> Bool
    /// Adds at the end; false if it was already queued or the queue is full.
    func add(videoID: UUID, title: String, creator: String, at date: Date) async -> Bool
    func remove(_ videoID: UUID) async
    /// Moves an entry `by` places (negative = up).
    func move(_ videoID: UUID, by offset: Int) async
    /// Marks it watched; returns the entry as it was before.
    func markWatched(_ videoID: UUID, at date: Date) async -> WatchLaterEntry?
    func clearWatched() async
    func clear() async
}

/// The queue rules, shared by the Core Data store and the in-memory one (same as Android's `WatchLaterRules`).
nonisolated enum WatchLaterRules {
    static let maxEntries = 100

    static func ordered(_ entries: [WatchLaterEntry]) -> [WatchLaterEntry] {
        entries.sorted { a, b in
            if a.isWatched != b.isWatched { return !a.isWatched }
            if a.position != b.position { return a.position < b.position }
            return a.addedAt < b.addedAt
        }
    }

    /// The unwatched queue after moving `videoID`, renumbered 0..n, followed by the watched entries.
    static func moved(_ entries: [WatchLaterEntry], _ videoID: UUID, by offset: Int) -> [WatchLaterEntry] {
        var queue = ordered(entries).filter { !$0.isWatched }
        guard offset != 0, let from = queue.firstIndex(where: { $0.videoID == videoID }) else { return entries }
        let to = min(max(from + offset, 0), queue.count - 1)
        let entry = queue.remove(at: from)
        queue.insert(entry, at: to)
        for index in queue.indices { queue[index].position = index }
        return queue + entries.filter(\.isWatched)
    }
}

/// A queued short that is still in the library, with the short.
struct WatchLaterItem: Identifiable {
    let video: VideoItem
    let entry: WatchLaterEntry
    var id: UUID { video.id }

    static func visible(_ entries: [WatchLaterEntry], in library: [VideoItem]) -> [WatchLaterItem] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return WatchLaterRules.ordered(entries).compactMap { entry in
            byID[entry.videoID].map { WatchLaterItem(video: $0, entry: entry) }
        }
    }
}

actor InMemoryWatchLaterStore: WatchLaterStoring {
    private var items: [WatchLaterEntry] = []

    func entries() async -> [WatchLaterEntry] { WatchLaterRules.ordered(items) }

    func contains(_ videoID: UUID) async -> Bool { items.contains { $0.videoID == videoID } }

    func add(videoID: UUID, title: String, creator: String, at date: Date) async -> Bool {
        guard !items.contains(where: { $0.videoID == videoID }), items.count < WatchLaterRules.maxEntries else { return false }
        let next = (items.map(\.position).max() ?? -1) + 1
        items.append(WatchLaterEntry(videoID: videoID, title: title, creator: creator, addedAt: date, position: next))
        return true
    }

    func remove(_ videoID: UUID) async { items.removeAll { $0.videoID == videoID } }

    func move(_ videoID: UUID, by offset: Int) async { items = WatchLaterRules.moved(items, videoID, by: offset) }

    func markWatched(_ videoID: UUID, at date: Date) async -> WatchLaterEntry? {
        guard let index = items.firstIndex(where: { $0.videoID == videoID }) else { return nil }
        let before = items[index]
        items[index].watchedAt = date
        return before
    }

    func clearWatched() async { items.removeAll(where: \.isWatched) }

    func clear() async { items = [] }
}

/// Core Data store (SQLite) for the queue: its own small model and file,
/// `WatchLater.sqlite`, next to "Recently viewed". Every call runs on a
/// background context queue (`perform`), never on the main thread.
nonisolated final class CoreDataWatchLaterStore: WatchLaterStoring, @unchecked Sendable {
    private static let entityName = "WatchLater"
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(accountID: UUID, inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentContainer(name: "WatchLater", managedObjectModel: Self.model)
        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            let folder = URL.applicationSupportDirectory.appending(path: "offline", directoryHint: .isDirectory)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = storeURL ?? folder.appending(path: "WatchLater-\(accountID.uuidString).sqlite")
            description = NSPersistentStoreDescription(url: url)
            description.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        }
        container.persistentStoreDescriptions = [description]
        let coordinator = container.persistentStoreCoordinator
        container.loadPersistentStores { _, error in
            if error != nil {
                _ = try? coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil)
            }
        }
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func entries() async -> [WatchLaterEntry] {
        await context.perform { [context] in
            WatchLaterRules.ordered(Self.fetchAll(context).compactMap(Self.entry(from:)))
        }
    }

    func contains(_ videoID: UUID) async -> Bool {
        await context.perform { [context] in Self.row(videoID, in: context) != nil }
    }

    func add(videoID: UUID, title: String, creator: String, at date: Date) async -> Bool {
        await context.perform { [context] in
            guard context.persistentStoreCoordinator?.persistentStores.isEmpty == false else { return false }
            let rows = Self.fetchAll(context)
            guard Self.row(videoID, in: context) == nil, rows.count < WatchLaterRules.maxEntries else { return false }
            let next = (rows.compactMap { $0.value(forKey: "position") as? Int64 }.max() ?? -1) + 1
            let row = NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context)
            row.setValue(videoID, forKey: "videoID")
            row.setValue(title, forKey: "title")
            row.setValue(creator, forKey: "creator")
            row.setValue(date, forKey: "addedAt")
            row.setValue(next, forKey: "position")
            return Self.save(context)
        }
    }

    func remove(_ videoID: UUID) async {
        await context.perform { [context] in
            if let row = Self.row(videoID, in: context) { context.delete(row) }
            _ = Self.save(context)
        }
    }

    func move(_ videoID: UUID, by offset: Int) async {
        await context.perform { [context] in
            let rows = Self.fetchAll(context)
            let moved = WatchLaterRules.moved(rows.compactMap(Self.entry(from:)), videoID, by: offset)
            for entry in moved where !entry.isWatched {
                rows.first { ($0.value(forKey: "videoID") as? UUID) == entry.videoID }?
                    .setValue(Int64(entry.position), forKey: "position")
            }
            _ = Self.save(context)
        }
    }

    func markWatched(_ videoID: UUID, at date: Date) async -> WatchLaterEntry? {
        await context.perform { [context] in
            guard let row = Self.row(videoID, in: context), let before = Self.entry(from: row) else { return nil }
            row.setValue(date, forKey: "watchedAt")
            return Self.save(context) ? before : nil
        }
    }

    func clearWatched() async {
        await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "watchedAt != nil")
            ((try? context.fetch(request)) ?? []).forEach(context.delete)
            _ = Self.save(context)
        }
    }

    func clear() async {
        await context.perform { [context] in
            Self.fetchAll(context).forEach(context.delete)
            _ = Self.save(context)
        }
    }

    private static func save(_ context: NSManagedObjectContext) -> Bool {
        do {
            try context.save()
            return true
        } catch {
            context.rollback()
            return false
        }
    }

    private static func fetchAll(_ context: NSManagedObjectContext) -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.sortDescriptors = [NSSortDescriptor(key: "position", ascending: true)]
        return (try? context.fetch(request)) ?? []
    }

    private static func row(_ videoID: UUID, in context: NSManagedObjectContext) -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "videoID == %@", videoID as CVarArg)
        request.fetchLimit = 1
        return (try? context.fetch(request))?.first
    }

    private static func entry(from row: NSManagedObject) -> WatchLaterEntry? {
        guard let id = row.value(forKey: "videoID") as? UUID,
              let added = row.value(forKey: "addedAt") as? Date else { return nil }
        return WatchLaterEntry(
            videoID: id,
            title: row.value(forKey: "title") as? String ?? "",
            creator: row.value(forKey: "creator") as? String ?? "",
            addedAt: added,
            position: Int(row.value(forKey: "position") as? Int64 ?? 0),
            watchedAt: row.value(forKey: "watchedAt") as? Date
        )
    }

    private static let model: NSManagedObjectModel = {
        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            return attribute
        }
        let entity = NSEntityDescription()
        entity.name = entityName
        entity.properties = [
            attribute("videoID", .UUIDAttributeType),
            attribute("title", .stringAttributeType),
            attribute("creator", .stringAttributeType),
            attribute("addedAt", .dateAttributeType),
            attribute("position", .integer64AttributeType),
            attribute("watchedAt", .dateAttributeType, optional: true),
        ]
        entity.uniquenessConstraints = [["videoID"]]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }()
}
