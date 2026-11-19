import Foundation

/// Measures how much disk removing a folder would give back.
///
/// `du` does this one file at a time, which on a cold cache of a million small files takes minutes.
/// This reads many folders at once, and asks for a whole folder's sizes in one go.
///
/// A file with several names (a hard link) only goes away with its last name. pnpm fills a project's
/// node_modules with links into its store, so deleting either one alone frees none of those files.
/// Such a file is counted only when every one of its names is inside the folders measured.
final class FolderSize {
    private static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .linkCountKey, .fileIdentifierKey,
    ]
    private static let keySet = Set(keys)

    private let lock = NSLock()
    private var total: UInt64 = 0
    /// Files with more than one name: how many of the names were met here, of how many, and the size.
    private var linked: [UInt64: (met: Int, names: Int, bytes: UInt64)] = [:]

    static func measure(_ paths: [String]) -> UInt64 {
        let size = FolderSize()
        for path in paths {
            size.walk(URL(fileURLWithPath: path, isDirectory: true))
        }
        return size.total + size.linked.values.filter { $0.met >= $0.names }.reduce(0) { $0 + $1.bytes }
    }

    private func walk(_ folder: URL) {
        guard let entries = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Self.keys, options: []) else { return }
        var folders: [URL] = []
        var bytes: UInt64 = 0
        var shared: [(id: UInt64, names: Int, bytes: UInt64)] = []
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Self.keySet) else { continue }
            if values.isSymbolicLink == true {
                continue
            } else if values.isDirectory == true {
                folders.append(entry)
            } else if values.isRegularFile == true {
                let size = UInt64(max(0, values.totalFileAllocatedSize ?? 0))
                if let names = values.linkCount, names > 1, let id = values.fileIdentifier {
                    shared.append((id, names, size))
                } else {
                    bytes += size
                }
            }
        }
        lock.lock()
        total += bytes
        for file in shared {
            linked[file.id, default: (0, file.names, file.bytes)].met += 1
        }
        lock.unlock()
        // The folders inside, several at a time. Reading them is waiting on the disk, not work, so
        // this is where the minutes go away.
        DispatchQueue.concurrentPerform(iterations: folders.count) { walk(folders[$0]) }
    }
}
