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
}
