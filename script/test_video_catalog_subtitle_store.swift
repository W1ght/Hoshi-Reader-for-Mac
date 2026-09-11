import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else {
        fputs("FAIL: \(message)\n", stderr)
        exit(1)
    }
}

@main
private enum VideoCatalogSubtitleStoreTests {
    static func main() {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("test-video-catalog-subtitles-\(UUID().uuidString)", isDirectory: true)
        let sourceDirectory = root.appendingPathComponent("downloads", isDirectory: true)
        try? fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

        // Archive copies the downloaded file into a per-video directory.
        let downloadURL = sourceDirectory.appendingPathComponent("subtitle-1").appendingPathExtension("ass")
        try? Data(" Dialogue: 0,0:00:01.00,0:00:02.00".utf8).write(to: downloadURL)
        let videoKey = URL(fileURLWithPath: "/tmp/media/Show Episode 01.mkv").standardizedFileURL.path
        let archivedURL = try! CatalogSubtitleStore.archive(
            fileAt: downloadURL,
            videoKey: videoKey,
            fileName: "Show - 01 [JA].ass",
            rootDirectory: root
        )
        expect(archivedURL.lastPathComponent == "Show - 01 [JA].ass", "archive should keep the source file name")
        expect(archivedURL.deletingLastPathComponent() != sourceDirectory, "archive should leave the temporary directory")
        expect(
            CatalogSubtitleStore.isManagedURL(archivedURL, rootDirectory: root),
            "archived subtitles should be recognized as Niratan-managed files"
        )
        expect(
            !CatalogSubtitleStore.isManagedURL(downloadURL, rootDirectory: root),
            "temporary downloads should not be mistaken for archived subtitles"
        )
        expect(
            (try? Data(contentsOf: archivedURL)) == Data(" Dialogue: 0,0:00:01.00,0:00:02.00".utf8),
            "archive should copy the downloaded bytes"
        )

        // Re-archiving the same catalog file overwrites instead of duplicating.
        try? Data(" Dialogue: 0,0:00:03.00,0:00:04.00".utf8).write(to: downloadURL)
        let reArchivedURL = try! CatalogSubtitleStore.archive(
            fileAt: downloadURL,
            videoKey: videoKey,
            fileName: "Show - 01 [JA].ass",
            rootDirectory: root
        )
        expect(reArchivedURL == archivedURL, "archive should be deterministic for the same video and file")
        expect(
            try! fileManager.contentsOfDirectory(atPath: archivedURL.deletingLastPathComponent().path).count == 1,
            "re-archiving should not duplicate files"
        )

        // A different video archives into its own directory.
        let otherVideoURL = try! CatalogSubtitleStore.archive(
            fileAt: downloadURL,
            videoKey: "remote://youtube/abc123",
            fileName: "Show - 01 [JA].ass",
            rootDirectory: root
        )
        expect(
            otherVideoURL.deletingLastPathComponent() != archivedURL.deletingLastPathComponent(),
            "different media identities should archive into separate directories"
        )

        // File names are sanitized and never gain a doubled extension.
        let slashDownload = sourceDirectory.appendingPathComponent("subtitle-2").appendingPathExtension("srt")
        try? Data("1".utf8).write(to: slashDownload)
        let sanitizedURL = try! CatalogSubtitleStore.archive(
            fileAt: slashDownload,
            videoKey: videoKey,
            fileName: "bad/name:here.srt",
            rootDirectory: root
        )
        expect(sanitizedURL.lastPathComponent == "bad-name-here.srt", "path separators should be sanitized away")
        let extensionlessURL = try! CatalogSubtitleStore.archive(
            fileAt: slashDownload,
            videoKey: videoKey,
            fileName: "unnamed subtitle",
            rootDirectory: root
        )
        expect(extensionlessURL.lastPathComponent == "unnamed subtitle.srt", "a missing extension should be appended")
        let doubledURL = try! CatalogSubtitleStore.archive(
            fileAt: slashDownload,
            videoKey: videoKey,
            fileName: "named.srt",
            rootDirectory: root
        )
        expect(doubledURL.lastPathComponent == "named.srt", "an existing extension should not be doubled")
        let emptyURL = try! CatalogSubtitleStore.archive(
            fileAt: slashDownload,
            videoKey: videoKey,
            fileName: "   ",
            rootDirectory: root
        )
        expect(emptyURL.lastPathComponent == "subtitle.srt", "an empty name should fall back to a stable default")

        // Maintenance removes only unreferenced files that aged past the
        // grace interval, and drops directories left empty.
        let videoDirectory = archivedURL.deletingLastPathComponent()
        let orphanURL = videoDirectory.appendingPathComponent("orphan.srt")
        try? Data("1".utf8).write(to: orphanURL)
        let staleDate = Date().addingTimeInterval(-(CatalogSubtitleStore.maintenanceGraceInterval + 60))
        try? fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: orphanURL.path)

        let freshOrphanURL = videoDirectory.appendingPathComponent("fresh.srt")
        try? Data("2".utf8).write(to: freshOrphanURL)

        let referencedStaleURL = videoDirectory.appendingPathComponent("referenced.srt")
        try? Data("3".utf8).write(to: referencedStaleURL)
        try? fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: referencedStaleURL.path)

        CatalogSubtitleStore.removeUnreferencedFiles(
            referencedFilePaths: [referencedStaleURL.standardizedFileURL.path],
            rootDirectory: root
        )
        expect(!fileManager.fileExists(atPath: orphanURL.path), "stale unreferenced files should be removed")
        expect(fileManager.fileExists(atPath: freshOrphanURL.path), "fresh unreferenced files should be spared")
        expect(fileManager.fileExists(atPath: referencedStaleURL.path), "referenced files should be spared")

        let goneArchiveURL = try! CatalogSubtitleStore.archive(
            fileAt: slashDownload,
            videoKey: "/tmp/media/Gone Episode 01.mkv",
            fileName: "gone.ass",
            rootDirectory: root
        )
        let emptyDirectory = goneArchiveURL.deletingLastPathComponent()
        try? fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: emptyDirectory.path)
        try? fileManager.removeItem(at: goneArchiveURL)

        CatalogSubtitleStore.removeUnreferencedFiles(referencedFilePaths: [], rootDirectory: root)
        expect(!fileManager.fileExists(atPath: emptyDirectory.path), "empty per-video directories should be removed")

        // The once-per-process guard makes repeat maintenance calls no-ops.
        let guardedOrphanURL = videoDirectory.appendingPathComponent("guarded.srt")
        try? Data("4".utf8).write(to: guardedOrphanURL)
        try? fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: guardedOrphanURL.path)
        CatalogSubtitleStore.performMaintenanceIfNeeded(referencedFilePaths: [], rootDirectory: root)
        expect(
            !fileManager.fileExists(atPath: guardedOrphanURL.path),
            "the first maintenance run should clean stale files"
        )

        let suppressedOrphanURL = videoDirectory.appendingPathComponent("suppressed.srt")
        try? Data("5".utf8).write(to: suppressedOrphanURL)
        try? fileManager.setAttributes([.modificationDate: staleDate], ofItemAtPath: suppressedOrphanURL.path)
        CatalogSubtitleStore.performMaintenanceIfNeeded(referencedFilePaths: [], rootDirectory: root)
        expect(
            fileManager.fileExists(atPath: suppressedOrphanURL.path),
            "repeat maintenance calls should be no-ops"
        )

        try? fileManager.removeItem(at: root)
        print("Video catalog subtitle store tests passed")
    }
}
