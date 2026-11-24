import Foundation

/// Where the Claude Code plugin tells seshka that a session has ended.
///
/// The plugin's hook runs for a moment as Claude Code closes. It leaves an empty file named after the
/// session in a folder, and seshka watches the folder. A file says only that the session ended: what
/// to do about it is decided here, by the user's settings.
enum Ended {
    static var folder: URL {
        History.file.deletingLastPathComponent().appendingPathComponent("ended")
    }

    /// The sessions announced and not yet put away, with when each was announced.
    static func pending() -> [String: Date] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var found: [String: Date] = [:]
        // Only a session ID is a name the plugin gives a file.
        for name in names where UUID(uuidString: name) != nil {
            let about = try? FileManager.default.attributesOfItem(atPath: folder.appendingPathComponent(name).path)
            found[name] = about?[.modificationDate] as? Date ?? Date()
        }
        return found
    }

    static func settle(_ session: String) {
        guard UUID(uuidString: session) != nil else { return }
        try? FileManager.default.removeItem(at: folder.appendingPathComponent(session))
    }

    /// Calls back on the main queue whenever something in the folder changes.
    static func watch(_ changed: @escaping () -> Void) -> DispatchSourceFileSystemObject? {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        source.setEventHandler(handler: changed)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}
