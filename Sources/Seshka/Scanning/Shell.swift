import Foundation

enum Shell {
    static func run(_ path: String, _ args: [String], environment: [String: String] = [:]) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        if !environment.isEmpty {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }
        }
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return "" }
        // Read before waiting, otherwise a full pipe blocks the child forever.
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }

    /// Runs a command whose failure matters: nil when it succeeded, otherwise what it complained about.
    static func failure(_ path: String, _ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        let complaints = Pipe()
        process.standardOutput = FileHandle.nullDevice
        process.standardError = complaints
        do { try process.run() } catch { return error.localizedDescription }
        let data = complaints.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus != 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "\((path as NSString).lastPathComponent) failed" : text
    }
}
