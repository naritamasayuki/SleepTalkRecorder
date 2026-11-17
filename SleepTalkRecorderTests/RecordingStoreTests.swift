import XCTest
@testable import SleepTalkRecorder

@MainActor
final class RecordingStoreTests: XCTestCase {
    private func makeTempDirectory() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SleepTalkRecorderTests_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func testAddLoadAndDeleteRecording() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = RecordingStore(directoryURL: tempDirectory)
        let fileName = "test_clip.m4a"
        let fileURL = tempDirectory.appendingPathComponent(fileName)
        try Data("dummy audio".utf8).write(to: fileURL)

        let item = RecordingItem(
            fileName: fileName,
            createdAt: Date(),
            duration: 4.5,
            peakDecibels: -18.2
        )
        store.add(item)
        XCTAssertEqual(store.recordings.count, 1)

        // 別インスタンスで再読み込みして永続化を検証
        let reloadedStore = RecordingStore(directoryURL: tempDirectory)
        XCTAssertEqual(reloadedStore.recordings.count, 1)
        XCTAssertEqual(reloadedStore.recordings.first?.fileName, fileName)

        // 削除時に実ファイルも消えること
        reloadedStore.delete(item)
        XCTAssertTrue(reloadedStore.recordings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testOrphanedMetadataWithoutAudioFileIsFilteredOut() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = RecordingStore(directoryURL: tempDirectory)
        let missingFileItem = RecordingItem(
            fileName: "missing.m4a",
            createdAt: Date(),
            duration: 2.0,
            peakDecibels: -25.0
        )
        store.add(missingFileItem)

        let reloadedStore = RecordingStore(directoryURL: tempDirectory)
        XCTAssertTrue(reloadedStore.recordings.isEmpty)
    }

    func testSettingsPersistenceAndClamping() {
        let suiteName = "SleepTalkRecorderSettingsTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let extremeSettings = RecorderSettings(
            thresholdDecibels: 10.0,
            silenceTimeoutSeconds: 99.0,
            minimumDurationSeconds: -5.0,
            preRollSeconds: 10.0,
            dimScreenDuringMonitoring: false
        )
        extremeSettings.save(to: defaults)

        let loaded = RecorderSettings.load(from: defaults)
        XCTAssertEqual(loaded.thresholdDecibels, -5.0)
        XCTAssertEqual(loaded.silenceTimeoutSeconds, 10.0)
        XCTAssertEqual(loaded.minimumDurationSeconds, 0.2)
        XCTAssertEqual(loaded.preRollSeconds, 3.0)
        XCTAssertFalse(loaded.dimScreenDuringMonitoring)
    }

    func testUpdateTranscriptRenamesFileAndHandlesDuplicates() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = RecordingStore(directoryURL: tempDirectory)

        let file1URL = tempDirectory.appendingPathComponent("raw_1.m4a")
        try Data("audio1".utf8).write(to: file1URL)
        let item1 = RecordingItem(fileName: "raw_1.m4a", duration: 2.0, peakDecibels: -20.0)
        store.add(item1)

        let file2URL = tempDirectory.appendingPathComponent("raw_2.m4a")
        try Data("audio2".utf8).write(to: file2URL)
        let item2 = RecordingItem(fileName: "raw_2.m4a", duration: 3.0, peakDecibels: -18.0)
        store.add(item2)

        store.updateTranscript(for: item1.id, transcript: "おやすみ")
        store.updateTranscript(for: item2.id, transcript: "おやすみ")

        let updated1 = store.recordings.first { $0.id == item1.id }
        let updated2 = store.recordings.first { $0.id == item2.id }

        XCTAssertEqual(updated1?.fileName, "おやすみ.m4a")
        XCTAssertEqual(updated1?.transcript, "おやすみ")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("おやすみ.m4a").path))

        XCTAssertEqual(updated2?.fileName, "おやすみ_2.m4a")
        XCTAssertEqual(updated2?.transcript, "おやすみ")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("おやすみ_2.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1URL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2URL.path))
    }
}
