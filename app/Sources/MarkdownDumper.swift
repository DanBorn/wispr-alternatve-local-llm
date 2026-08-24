import Foundation

struct MarkdownDumpResult {
    let noteURL: URL
    let attachmentURLs: [URL]
}

final class MarkdownDumper: @unchecked Sendable {
    private let config: AppConfig
    private let now: @Sendable () -> Date

    init(config: AppConfig, now: @escaping @Sendable () -> Date = Date.init) {
        self.config = config
        self.now = now
    }

    func dump(transcript: String) async throws -> URL {
        try dumpRaw(transcript)
    }

    func dumpRaw(_ text: String) throws -> URL {
        try dumpRaw(text, imageURLs: []).noteURL
    }

    func dumpRaw(_ text: String, imageURLs: [URL]) throws -> MarkdownDumpResult {
        let fileManager = FileManager.default
        let fileURL = config.dump.markdownURL
        let directoryURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let timestamp = now()
        let attachmentPlan = makeAttachmentPlan(
            imageURLs: imageURLs,
            noteDirectoryURL: directoryURL,
            timestamp: timestamp
        )
        let attachmentDateDirectory = attachmentPlan.first?.destination.deletingLastPathComponent()
        let attachmentRootDirectory = attachmentDateDirectory?.deletingLastPathComponent()
        let attachmentDateDirectoryExisted = attachmentDateDirectory.map {
            fileManager.fileExists(atPath: $0.path)
        } ?? true
        let attachmentRootDirectoryExisted = attachmentRootDirectory.map {
            fileManager.fileExists(atPath: $0.path)
        } ?? true
        var copiedURLs: [URL] = []

        do {
            if !attachmentPlan.isEmpty {
                try fileManager.createDirectory(
                    at: attachmentPlan[0].destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            }
            for attachment in attachmentPlan {
                let data = try Data(contentsOf: attachment.source)
                guard !fileManager.fileExists(atPath: attachment.destination.path) else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try data.write(to: attachment.destination, options: .atomic)
                copiedURLs.append(attachment.destination)
            }

            let embeds = attachmentPlan.enumerated().map { index, attachment in
                "![Screenshot \(index + 1)](\(attachment.relativePath))"
            }
            let entry = formatEntry(text, imageEmbeds: embeds, timestamp: timestamp)
            let existingData: Data
            if config.dump.append, fileManager.fileExists(atPath: fileURL.path) {
                existingData = try Data(contentsOf: fileURL)
            } else {
                existingData = Data()
            }
            var completeData = existingData
            completeData.append(Data(entry.utf8))
            try completeData.write(to: fileURL, options: .atomic)
            return MarkdownDumpResult(noteURL: fileURL, attachmentURLs: copiedURLs)
        } catch {
            for url in copiedURLs {
                try? fileManager.removeItem(at: url)
            }
            if !attachmentDateDirectoryExisted, let attachmentDateDirectory {
                try? fileManager.removeItem(at: attachmentDateDirectory)
            }
            if !attachmentRootDirectoryExisted, let attachmentRootDirectory,
               (try? fileManager.contentsOfDirectory(atPath: attachmentRootDirectory.path).isEmpty) == true {
                try? fileManager.removeItem(at: attachmentRootDirectory)
            }
            throw error
        }
    }

    private struct AttachmentPlan {
        let source: URL
        let destination: URL
        let relativePath: String
    }

    private func makeAttachmentPlan(
        imageURLs: [URL],
        noteDirectoryURL: URL,
        timestamp: Date
    ) -> [AttachmentPlan] {
        guard !imageURLs.isEmpty else {
            return []
        }
        let dateFolder = dateString(timestamp)
        let runID = "fluid-ptt-\(timestampString(timestamp))-\(UUID().uuidString.lowercased())"
        return imageURLs.enumerated().map { index, source in
            let fileExtension = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
            let filename = String(format: "%@-%02d.%@", runID, index + 1, fileExtension)
            let relativePath = "attachments/\(dateFolder)/\(filename)"
            return AttachmentPlan(
                source: source,
                destination: noteDirectoryURL.appendingPathComponent(relativePath),
                relativePath: relativePath
            )
        }
    }

    private func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func timestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter.string(from: date)
    }

    private func formatEntry(_ markdown: String, imageEmbeds: [String], timestamp: Date) -> String {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        let content = ([trimmed] + imageEmbeds)
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        guard config.dump.includeTimestamp else {
            return "\n\n\(content)\n"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return "\n\n\(formatter.string(from: timestamp))\n\(content)\n"
    }
}
