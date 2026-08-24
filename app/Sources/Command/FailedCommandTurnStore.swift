import CryptoKit
import Darwin
import Foundation

struct FailedCommandTurnManifest: Codable {
    let createdAt: String
    let provider: String
    let model: String
    let information: String
    let command: String
    let error: String
    let images: [Image]

    struct Image: Codable {
        let originalPath: String
        let retainedFilename: String
        let byteCount: Int
        let sha256: String

        enum CodingKeys: String, CodingKey {
            case originalPath = "original_path"
            case retainedFilename = "retained_filename"
            case byteCount = "byte_count"
            case sha256
        }
    }

    enum CodingKeys: String, CodingKey {
        case createdAt = "created_at"
        case provider, model, information, command, error, images
    }

}

final class FailedCommandTurnStore: @unchecked Sendable {
    static let defaultRootURL = URL(
        fileURLWithPath: "~/Library/Application Support/fluid-push-to-talk/last-failed-command".expandingTilde,
        isDirectory: true
    )

    let rootURL: URL
    private let beforePromote: @Sendable () throws -> Void

    init(
        rootURL: URL = FailedCommandTurnStore.defaultRootURL,
        beforePromote: @escaping @Sendable () throws -> Void = {}
    ) {
        self.rootURL = rootURL
        self.beforePromote = beforePromote
        do {
            try recoverIfNeeded()
        } catch {
            fputs("failed command turn recovery failed: \(error)\n", stderr)
        }
    }

    func retain(
        provider: String,
        model: String,
        information: String,
        command: String,
        errorDescription: String,
        imageURLs: [URL]
    ) throws {
        let fileManager = FileManager.default
        let parentURL = rootURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        let artifactPrefix = ".\(rootURL.lastPathComponent)"
        let stagingURL = parentURL.appendingPathComponent(
            "\(artifactPrefix).tmp-\(UUID().uuidString)",
            isDirectory: true
        )
        let backupURL = parentURL.appendingPathComponent(
            "\(artifactPrefix).backup-\(UUID().uuidString)",
            isDirectory: true
        )
        var movedPreviousToBackup = false
        var promotedStagingToRoot = false

        do {
            try fileManager.createDirectory(at: stagingURL, withIntermediateDirectories: true)
            try enforcePermissions(stagingURL, mode: S_IRWXU)
            var images: [FailedCommandTurnManifest.Image] = []
            for (index, sourceURL) in imageURLs.enumerated() {
                let data = try Data(contentsOf: sourceURL)
                let pathExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
                let filename = String(format: "image-%02d.%@", index + 1, pathExtension)
                let destinationURL = stagingURL.appendingPathComponent(filename)
                try data.write(to: destinationURL, options: .atomic)
                try enforcePermissions(destinationURL, mode: S_IRUSR | S_IWUSR)
                images.append(.init(
                    originalPath: sourceURL.path,
                    retainedFilename: filename,
                    byteCount: data.count,
                    sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                ))
            }

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let manifest = FailedCommandTurnManifest(
                createdAt: formatter.string(from: Date()),
                provider: provider,
                model: model,
                information: information,
                command: command,
                error: errorDescription,
                images: images
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            let manifestURL = stagingURL.appendingPathComponent("turn.json")
            try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
            try enforcePermissions(manifestURL, mode: S_IRUSR | S_IWUSR)

            if fileManager.fileExists(atPath: rootURL.path) {
                try fileManager.moveItem(at: rootURL, to: backupURL)
                movedPreviousToBackup = true
            }
            try beforePromote()
            try fileManager.moveItem(at: stagingURL, to: rootURL)
            promotedStagingToRoot = true
            try enforcePermissions(rootURL, mode: S_IRWXU)
            if movedPreviousToBackup {
                try fileManager.removeItem(at: backupURL)
            }
        } catch {
            if promotedStagingToRoot, fileManager.fileExists(atPath: rootURL.path) {
                try? fileManager.removeItem(at: rootURL)
            }
            if movedPreviousToBackup, fileManager.fileExists(atPath: backupURL.path) {
                do {
                    try fileManager.moveItem(at: backupURL, to: rootURL)
                } catch {
                    fputs("failed command turn rollback failed: \(error)\n", stderr)
                }
            }
            try? fileManager.removeItem(at: stagingURL)
            throw error
        }
    }

    func clear() throws {
        guard FileManager.default.fileExists(atPath: rootURL.path) else {
            return
        }
        try FileManager.default.removeItem(at: rootURL)
    }

    func recoverIfNeeded() throws {
        let fileManager = FileManager.default
        let parentURL = rootURL.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parentURL.path) else {
            return
        }
        let urls = try fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        let artifactPrefix = ".\(rootURL.lastPathComponent)"
        let backups = newestFirst(urls.filter {
            $0.lastPathComponent.hasPrefix("\(artifactPrefix).backup-")
        })
        let allStaging = newestFirst(urls.filter {
            $0.lastPathComponent.hasPrefix("\(artifactPrefix).tmp-")
        })
        let promotableStaging = allStaging.filter {
            fileManager.fileExists(atPath: $0.appendingPathComponent("turn.json").path)
        }

        if !fileManager.fileExists(atPath: rootURL.path) {
            if let backup = backups.first {
                try fileManager.moveItem(at: backup, to: rootURL)
                try enforcePermissions(rootURL, mode: S_IRWXU)
            } else if let staged = promotableStaging.first {
                try fileManager.moveItem(at: staged, to: rootURL)
                try enforcePermissions(rootURL, mode: S_IRWXU)
            }
        }

        let currentPaths = Set([rootURL.standardizedFileURL.path])
        for orphan in backups + allStaging where !currentPaths.contains(orphan.standardizedFileURL.path) {
            if fileManager.fileExists(atPath: orphan.path) {
                try fileManager.removeItem(at: orphan)
            }
        }
    }

    private func newestFirst(_ urls: [URL]) -> [URL] {
        urls.sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate > rhsDate
        }
    }

    private func enforcePermissions(_ url: URL, mode: mode_t) throws {
        guard chmod(url.path, mode) == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [
                    NSLocalizedDescriptionKey: "failed to set permissions \(String(mode, radix: 8)) on \(url.path)"
                ]
            )
        }
    }
}
