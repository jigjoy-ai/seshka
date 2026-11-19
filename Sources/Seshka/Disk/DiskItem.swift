import Foundation

/// Something on disk that can be removed: a worktree Claude Code made, the scratch files of closed
/// sessions, or a cache that fills up again on its own.
struct DiskItem: Identifiable, Equatable, Codable {
    enum Kind: Int, CaseIterable, Codable {
        case worktree, scratch, cache
    }

    enum State: Equatable, Codable {
        case removable
        /// A worktree with changes that were never committed. It is moved to the Trash, never deleted.
        case uncommitted
        /// In use, and why. Not offered for removal.
        case busy(String)
    }

    let id: String
    let kind: Kind
    let title: String
    var detail: String
    /// Everything that goes when this item is removed.
    let paths: [String]
    var state: State
    /// What removing it costs, when it costs anything.
    var note: String?
    /// For a worktree: the repository's main folder.
    var repository: String?
    /// Nil until measured.
    var bytes: UInt64?
}
