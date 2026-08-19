import Foundation

/// What the app is using on disk, for Settings' "Storage used".
enum StoreSize {

    /// The store's size, counting the files SQLite keeps beside it.
    ///
    /// In WAL mode a write lands in `-wal` and only reaches the store file at a
    /// checkpoint, so the store file alone understates what the app occupies.
    /// `-shm` is deliberately not counted: it is a shared-memory index that
    /// exists only while the store is open and is the same ~32 KB whatever the
    /// reader has, so charging it to them says nothing.
    ///
    /// Deleting rows does not shrink the file — SQLite frees the pages for
    /// reuse rather than returning them — so pruning buys a figure that stops
    /// climbing rather than one that drops (#18). Right after a Pack switch it
    /// can even rise, as the deletes sit in `-wal` waiting for a checkpoint.
    static func onDisk(_ storeURL: URL, fileManager: FileManager = .default) -> Int64 {
        let writeAheadLog = storeURL.deletingLastPathComponent()
            .appending(path: storeURL.lastPathComponent + "-wal")
        return [storeURL, writeAheadLog].reduce(into: Int64(0)) { total, url in
            total += (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? 0
        }
    }

    /// Where the app's own store lives.
    static var appStoreURL: URL {
        URL.applicationSupportDirectory.appending(path: "default.store")
    }
}
