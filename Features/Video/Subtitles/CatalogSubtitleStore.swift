import Foundation

nonisolated enum CatalogSubtitleSource: String, Sendable {
    case jimaku
    case ajatt

    var allowedDownloadHosts: Set<String>? {
        switch self {
        case .jimaku: nil
        case .ajatt: ["raw.githubusercontent.com"]
        }
    }

    var errorMessage: String {
        switch self {
        case .jimaku:
            String(localized: "Unable to load the Jimaku subtitle.")
        case .ajatt:
            String(localized: "Unable to load the AJATT subtitle.")
        }
    }

    var maximumResponseSize: Int {
        switch self {
        case .jimaku: 64 * 1_024 * 1_024
        case .ajatt: 10 * 1_024 * 1_024
        }
    }
}

/// Owns Niratan's durable copies of subtitles downloaded from subtitle
/// catalogs so a remembered `.external` selection keeps resolving after the
/// remote loader's temporary file is cleaned up. Files are grouped in one
/// directory per media identity and never touch the user's media folders.
nonisolated enum CatalogSubtitleStore {
    /// Recently written files are spared by maintenance so a concurrent
    /// window can still be loading the file its selection is about to
    /// reference.
    nonisolated static let maintenanceGraceInterval: TimeInterval = 24 * 60 * 60

    nonisolated private static let maximumFileNameLength = 120
    nonisolated private static let fallbackFileName = "subtitle"

    nonisolated private final class MaintenanceState: @unchecked Sendable {
        private let lock = NSLock()
        private var hasRun = false

        func markPerformedIfNeeded() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if hasRun {
                return false
            }
            hasRun = true
            return true
        }
    }

    nonisolated private static let maintenanceState = MaintenanceState()

    static func archive(
        fileAt sourceURL: URL,
        videoKey: String,
        fileName: String,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> URL {
        let directory = videoDirectory(
            videoKey: videoKey,
            rootDirectory: rootDirectory ?? defaultRootDirectory(fileManager: fileManager)
        )
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destinationURL = directory.appendingPathComponent(
            archivedFileName(fileName: fileName, pathExtension: sourceURL.pathExtension)
        )
        try Data(contentsOf: sourceURL).write(to: destinationURL, options: .atomic)
        return destinationURL
    }

    /// Runs once per process; subsequent calls are no-ops.
    static func performMaintenanceIfNeeded(
        referencedFilePaths: Set<String>,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        guard maintenanceState.markPerformedIfNeeded() else { return }
        removeUnreferencedFiles(
            referencedFilePaths: referencedFilePaths,
            rootDirectory: rootDirectory,
            fileManager: fileManager
        )
    }

    static func removeUnreferencedFiles(
        referencedFilePaths: Set<String>,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) {
        let rootDirectory = rootDirectory ?? defaultRootDirectory(fileManager: fileManager)
        let graceCutoff = Date().addingTimeInterval(-maintenanceGraceInterval)
        guard let videoDirectories = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: []
        ) else {
            return
        }
        for directory in videoDirectories {
            guard let fileURLs = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
                options: []
            ) else {
                continue
            }
            var remainingFiles = 0
            for fileURL in fileURLs {
                let isReferenced = referencedFilePaths.contains(
                    fileURL.standardizedFileURL.path
                )
                let isFresh = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate.map { $0 >= graceCutoff } ?? true
                if isReferenced || isFresh {
                    remainingFiles += 1
                    continue
                }
                try? fileManager.removeItem(at: fileURL)
            }
            if remainingFiles == 0 {
                try? fileManager.removeItem(at: directory)
            }
        }
    }

    nonisolated static func defaultRootDirectory(fileManager: FileManager) -> URL {
        let directory = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? fileManager.temporaryDirectory
        return directory.appendingPathComponent("VideoCatalogSubtitles", isDirectory: true)
    }

    static func isManagedURL(
        _ url: URL,
        rootDirectory: URL? = nil,
        fileManager: FileManager = .default
    ) -> Bool {
        let root = (rootDirectory ?? defaultRootDirectory(fileManager: fileManager))
            .standardizedFileURL
        let candidate = url.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        guard candidate.path.hasPrefix(rootPath) else { return false }
        let relativeComponents = candidate.path
            .dropFirst(rootPath.count)
            .split(separator: "/")
        guard relativeComponents.count >= 2,
              relativeComponents[0].count == 16 else {
            return false
        }
        return relativeComponents[0].allSatisfy { character in
            character.isHexDigit
        }
    }

    private static func videoDirectory(
        videoKey: String,
        rootDirectory: URL
    ) -> URL {
        rootDirectory.appendingPathComponent(fnv1a64(videoKey), isDirectory: true)
    }

    private static func archivedFileName(fileName: String, pathExtension: String) -> String {
        let sanitizedBase = String(
            fileName
                .map { character -> Character in
                    character == "/" || character == ":" ? "-" : character
                }
                .filter { !$0.isNewline && !$0.unicodeScalars.contains { $0.value < 32 || $0.value == 127 } }
                .prefix(maximumFileNameLength)
        )
        let trimmedBase = sanitizedBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmedBase.isEmpty ? fallbackFileName : trimmedBase
        let normalizedExtension = pathExtension.lowercased()
        guard !normalizedExtension.isEmpty else {
            return base
        }
        if base.lowercased().hasSuffix(".\(normalizedExtension)") {
            return base
        }
        return "\(base).\(normalizedExtension)"
    }

    private static func fnv1a64(_ string: String) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        return String(format: "%016llx", hash)
    }
}
