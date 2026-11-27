import CoreData
import Foundation
import Observation
import SwiftUI

/// "Recently viewed" (Sprint 3, David · local storage with a relational
/// database). Every time a short's detail screen opens it is recorded here,
/// and the Library shows the latest ones in a row. Same feature as the Room
/// table on Android.
nonisolated struct RecentlyViewedEntry: Equatable, Sendable, Identifiable {
    let videoID: UUID
    let title: String
    let platformRaw: String
    let creator: String
    let thumbnailURL: URL?
    let lastViewedAt: Date
    let viewCount: Int

    var id: UUID { videoID }

    init(
        videoID: UUID, title: String, platformRaw: String, creator: String,
        thumbnailURL: URL?, lastViewedAt: Date, viewCount: Int
    ) {
        self.videoID = videoID
        self.title = title
        self.platformRaw = platformRaw
        self.creator = creator
        self.thumbnailURL = thumbnailURL
        self.lastViewedAt = lastViewedAt
        self.viewCount = viewCount
    }

    /// Built on the main actor, where the screens hold their `VideoItem`s.
    @MainActor
    init(video: VideoItem, at date: Date = .now) {
        self.init(
            videoID: video.id,
            title: video.displayTitle,
            platformRaw: video.platform.rawValue,
            creator: video.creator,
            thumbnailURL: video.thumbnailURL,
            lastViewedAt: date,
            viewCount: 1
        )
    }
}

nonisolated protocol RecentlyViewedStoring: Sendable {
    /// Newest first.
    func recent(limit: Int) async -> [RecentlyViewedEntry]
    /// One more view of `entry.videoID` (its count goes up by one).
    func record(_ entry: RecentlyViewedEntry) async
    func remove(videoID: UUID) async
    func clear() async
}

/// A short to show in the "Recently viewed" row, with its history entry.
struct RecentlyViewedItem: Identifiable {
    let video: VideoItem
    let entry: RecentlyViewedEntry
    var id: UUID { video.id }
}

nonisolated enum RecentlyViewed {
    static let shownInLibrary = 10
    static let maxStored = 50

    /// Entries whose short is still in the library, in the entries' order.
    @MainActor
    static func videos(
        for entries: [RecentlyViewedEntry],
        in library: [VideoItem]
    ) -> [RecentlyViewedItem] {
        let byID = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return entries.compactMap { entry in
            byID[entry.videoID].map { RecentlyViewedItem(video: $0, entry: entry) }
        }
    }
}

/// Local storage with **Core Data** (SQLite underneath).
///
/// Why a relational store here and JSON files for the library copy: this data
/// is queried, not read whole. "The last 10 viewed" is a sorted fetch with a
/// limit, another view of the same short updates one row, and trimming the
/// history to 50 rows deletes only the old ones.
///
/// Threading: every call runs on Core Data's own background context queue
/// (`newBackgroundContext()` + `perform`), so the main thread never touches
/// SQLite. The model is built in code, so there is no .xcdatamodeld file.
nonisolated final class CoreDataRecentlyViewedStore: RecentlyViewedStoring, @unchecked Sendable {
    private static let entityName = "RecentlyViewed"
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(inMemory: Bool = false, storeURL: URL? = nil) {
        container = NSPersistentContainer(name: "RecentlyViewed", managedObjectModel: Self.model)
        let description: NSPersistentStoreDescription
        if inMemory {
            description = NSPersistentStoreDescription()
            description.type = NSInMemoryStoreType
        } else {
            let url = storeURL ?? URL.applicationSupportDirectory
                .appending(path: "offline/RecentlyViewed.sqlite", directoryHint: .notDirectory)
            let folder = url.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            description = NSPersistentStoreDescription(url: url)
            description.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)
        }
        container.persistentStoreDescriptions = [description]
        let coordinator = container.persistentStoreCoordinator
        container.loadPersistentStores { _, error in
            if error != nil {
                _ = try? coordinator.addPersistentStore(ofType: NSInMemoryStoreType, configurationName: nil, at: nil, options: nil)
            }
        }
        context = container.newBackgroundContext()
        context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    func recent(limit: Int) async -> [RecentlyViewedEntry] {
        guard limit > 0 else { return [] }
        return await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.sortDescriptors = [NSSortDescriptor(key: "lastViewedAt", ascending: false)]
            request.fetchLimit = limit
            return ((try? context.fetch(request)) ?? []).compactMap(Self.entry(from:))
        }
    }

    func record(_ entry: RecentlyViewedEntry) async {
        await context.perform { [context] in
            guard context.persistentStoreCoordinator?.persistentStores.isEmpty == false else { return }
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "videoID == %@", entry.videoID as CVarArg)
            request.fetchLimit = 1
            do {
                let row = try context.fetch(request).first
                    ?? NSEntityDescription.insertNewObject(forEntityName: Self.entityName, into: context)
                let previous = row.value(forKey: "viewCount") as? Int64 ?? 0
                row.setValue(entry.videoID, forKey: "videoID")
                row.setValue(entry.title, forKey: "title")
                row.setValue(entry.platformRaw, forKey: "platform")
                row.setValue(entry.creator, forKey: "creator")
                row.setValue(entry.thumbnailURL?.absoluteString, forKey: "thumbnailURL")
                row.setValue(entry.lastViewedAt, forKey: "lastViewedAt")
                row.setValue(previous + 1, forKey: "viewCount")
                try Self.trim(context, keep: RecentlyViewed.maxStored)
                try context.save()
            } catch {
                context.rollback()
            }
        }
    }

    func remove(videoID: UUID) async {
        await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            request.predicate = NSPredicate(format: "videoID == %@", videoID as CVarArg)
            Self.deleteRows(matching: request, in: context)
        }
    }

    func clear() async {
        await context.perform { [context] in
            let request = NSFetchRequest<NSManagedObject>(entityName: Self.entityName)
            Self.deleteRows(matching: request, in: context)
        }
    }

    private static func deleteRows(matching request: NSFetchRequest<NSManagedObject>, in context: NSManagedObjectContext) {
        do {
            try context.fetch(request).forEach(context.delete)
            try context.save()
        } catch {
            context.rollback()
        }
    }

    /// Deletes every row older than the newest `keep`.
    private static func trim(_ context: NSManagedObjectContext, keep: Int) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.sortDescriptors = [NSSortDescriptor(key: "lastViewedAt", ascending: false)]
        try context.fetch(request).dropFirst(keep).forEach(context.delete)
    }

    private static func entry(from row: NSManagedObject) -> RecentlyViewedEntry? {
        guard let id = row.value(forKey: "videoID") as? UUID,
              let date = row.value(forKey: "lastViewedAt") as? Date else { return nil }
        return RecentlyViewedEntry(
            videoID: id,
            title: row.value(forKey: "title") as? String ?? "",
            platformRaw: row.value(forKey: "platform") as? String ?? "",
            creator: row.value(forKey: "creator") as? String ?? "",
            thumbnailURL: (row.value(forKey: "thumbnailURL") as? String).flatMap(URL.init(string:)),
            lastViewedAt: date,
            viewCount: Int(row.value(forKey: "viewCount") as? Int64 ?? 1)
        )
    }

    /// The table, defined in code: one row per short.
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
            attribute("platform", .stringAttributeType),
            attribute("creator", .stringAttributeType),
            attribute("thumbnailURL", .stringAttributeType, optional: true),
            attribute("lastViewedAt", .dateAttributeType),
            attribute("viewCount", .integer64AttributeType),
        ]
        entity.uniquenessConstraints = [["videoID"]]
        let model = NSManagedObjectModel()
        model.entities = [entity]
        return model
    }()
}

/// Same behaviour, in memory: the mock build, previews and tests.
actor InMemoryRecentlyViewedStore: RecentlyViewedStoring {
    private var entries: [RecentlyViewedEntry] = []

    func recent(limit: Int) async -> [RecentlyViewedEntry] {
        Array(entries.prefix(max(0, limit)))
    }

    func record(_ entry: RecentlyViewedEntry) async {
        let previous = entries.first { $0.videoID == entry.videoID }?.viewCount ?? 0
        entries.removeAll { $0.videoID == entry.videoID }
        entries.append(RecentlyViewedEntry(
            videoID: entry.videoID, title: entry.title, platformRaw: entry.platformRaw,
            creator: entry.creator, thumbnailURL: entry.thumbnailURL,
            lastViewedAt: entry.lastViewedAt, viewCount: previous + 1
        ))
        entries = Array(entries.sorted { $0.lastViewedAt > $1.lastViewedAt }.prefix(RecentlyViewed.maxStored))
    }

    func remove(videoID: UUID) async {
        entries.removeAll { $0.videoID == videoID }
    }

    func clear() async {
        entries = []
    }
}

/// Publishes completed writes to the Library and orders sign-out cleanup with visits.
@MainActor
@Observable
final class RecentlyViewedHistory {
    private let store: any RecentlyViewedStoring
    @ObservationIgnored private var pendingWrite: Task<Void, Never>?
    private(set) var revision = 0

    init(store: any RecentlyViewedStoring) {
        self.store = store
    }

    func recent(limit: Int) async -> [RecentlyViewedEntry] {
        await pendingWrite?.value
        return await store.recent(limit: limit)
    }

    func record(_ entry: RecentlyViewedEntry) async {
        let write = enqueue { await $0.record(entry) }
        await write.value
    }

    func clear() {
        _ = enqueue { await $0.clear() }
    }

    private func enqueue(_ operation: @escaping (any RecentlyViewedStoring) async -> Void) -> Task<Void, Never> {
        let previous = pendingWrite
        let store = self.store
        let write = Task { [weak self] in
            await previous?.value
            await operation(store)
            self?.revision += 1
        }
        pendingWrite = write
        return write
    }
}

extension EnvironmentValues {
    @Entry var recentlyViewed: RecentlyViewedHistory? = nil
}
