import AVFoundation
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

    private func writeSilentM4A(to url: URL, seconds: Double = 0.5) throws {
        let sampleRate = 44_100.0
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1))
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: 1
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        try file.write(from: buffer)
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

        store.deleteAll()
        XCTAssertTrue(store.recordings.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("おやすみ.m4a").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("おやすみ_2.m4a").path))
    }

    func testLegacySettingsJsonDecodesWithDefaults() throws {
        let legacyJSON = """
        {
          "thresholdDecibels": -30.0,
          "silenceTimeoutSeconds": 4.0,
          "minimumDurationSeconds": 1.0,
          "preRollSeconds": 2.0,
          "dimScreenDuringMonitoring": false
        }
        """
        let decoded = try JSONDecoder().decode(RecorderSettings.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.thresholdDecibels, -30.0)
        XCTAssertTrue(decoded.transcribeForFileName)
        XCTAssertEqual(decoded.startDelayMinutes, 0)
        XCTAssertEqual(decoded.autoStopHours, 8)
    }

    func testToggleFavoriteAndDeleteNonFavorites() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = RecordingStore(directoryURL: tempDirectory)

        let favURL = tempDirectory.appendingPathComponent("fav.m4a")
        let normalURL = tempDirectory.appendingPathComponent("normal.m4a")
        try Data("a".utf8).write(to: favURL)
        try Data("b".utf8).write(to: normalURL)

        let favItem = RecordingItem(fileName: "fav.m4a", duration: 2.0, peakDecibels: -20.0)
        let normalItem = RecordingItem(fileName: "normal.m4a", duration: 1.5, peakDecibels: -25.0)
        store.add(favItem)
        store.add(normalItem)

        store.toggleFavorite(for: favItem.id)
        XCTAssertTrue(store.recordings.first { $0.id == favItem.id }?.isFavorite == true)

        store.deleteNonFavorites()
        XCTAssertEqual(store.recordings.count, 1)
        XCTAssertEqual(store.recordings.first?.id, favItem.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: favURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: normalURL.path))
    }

    func testGroupedByDaySortsNewestDaysFirst() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 9 * 3600)!

        let day1 = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 20, hour: 2, minute: 0)))
        let day2Morning = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 1, minute: 0)))
        let day2Late = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 21, hour: 4, minute: 0)))

        let items = [
            RecordingItem(fileName: "1.m4a", createdAt: day1, duration: 1.0, peakDecibels: -20.0),
            RecordingItem(fileName: "2.m4a", createdAt: day2Morning, duration: 1.0, peakDecibels: -20.0),
            RecordingItem(fileName: "3.m4a", createdAt: day2Late, duration: 1.0, peakDecibels: -20.0)
        ]

        let sections = RecordingStore.groupedByDay(items, calendar: calendar)
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].items.map(\.fileName), ["3.m4a", "2.m4a"])
        XCTAssertEqual(sections[1].items.map(\.fileName), ["1.m4a"])
    }

    func testRecoversValidEntriesWhenOneJsonItemIsCorrupt() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let validFileURL = tempDirectory.appendingPathComponent("valid.m4a")
        try Data("audio".utf8).write(to: validFileURL)

        let partialCorruptJSON = """
        [
          {
            "id": "11111111-1111-1111-1111-111111111111",
            "fileName": "valid.m4a",
            "createdAt": "2026-11-27T01:00:00Z",
            "duration": 3.2,
            "peakDecibels": -22.0,
            "isFavorite": true
          },
          {
            "brokenField": 12345
          }
        ]
        """
        try Data(partialCorruptJSON.utf8).write(to: tempDirectory.appendingPathComponent("recordings.json"))

        let store = RecordingStore(directoryURL: tempDirectory)
        XCTAssertEqual(store.recordings.count, 1)
        XCTAssertEqual(store.recordings.first?.fileName, "valid.m4a")
        XCTAssertEqual(store.recordings.first?.isFavorite, true)
        XCTAssertNotNil(store.lastErrorMessage)
    }

    func testBacksUpCorruptJsonAndRecoversOrphanedM4A() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let orphanURL = tempDirectory.appendingPathComponent("sleeptalk_orphan.m4a")
        try writeSilentM4A(to: orphanURL)
        // 再生不可能な壊れたm4aは復元対象外になることもあわせて確認
        let brokenURL = tempDirectory.appendingPathComponent("broken_orphan.m4a")
        try Data("not an audio file".utf8).write(to: brokenURL)
        try Data("{ invalid json !!!".utf8).write(to: tempDirectory.appendingPathComponent("recordings.json"))

        let store = RecordingStore(directoryURL: tempDirectory)
        XCTAssertEqual(store.recordings.count, 1)
        XCTAssertEqual(store.recordings.first?.fileName, "sleeptalk_orphan.m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDirectory.appendingPathComponent("recordings.corrupt.json").path))
        XCTAssertNotNil(store.lastErrorMessage)
    }

    func testDeleteNonFavoritesOlderThanDaysKeepsFavoritesAndRecent() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }

        let store = RecordingStore(directoryURL: tempDirectory)
        let now = Date()
        let oldDate = now.addingTimeInterval(-40 * 24 * 60 * 60)
        let recentDate = now.addingTimeInterval(-5 * 24 * 60 * 60)

        let oldNormalURL = tempDirectory.appendingPathComponent("old_normal.m4a")
        let oldFavURL = tempDirectory.appendingPathComponent("old_fav.m4a")
        let recentNormalURL = tempDirectory.appendingPathComponent("recent_normal.m4a")
        try Data("a".utf8).write(to: oldNormalURL)
        try Data("b".utf8).write(to: oldFavURL)
        try Data("c".utf8).write(to: recentNormalURL)

        store.add(RecordingItem(fileName: "old_normal.m4a", createdAt: oldDate, duration: 2.0, peakDecibels: -20.0, isFavorite: false))
        store.add(RecordingItem(fileName: "old_fav.m4a", createdAt: oldDate, duration: 2.0, peakDecibels: -20.0, isFavorite: true))
        store.add(RecordingItem(fileName: "recent_normal.m4a", createdAt: recentDate, duration: 2.0, peakDecibels: -20.0, isFavorite: false))

        let deletedCount = store.deleteNonFavorites(olderThanDays: 30, now: now)
        XCTAssertEqual(deletedCount, 1)
        XCTAssertEqual(Set(store.recordings.map(\.fileName)), ["old_fav.m4a", "recent_normal.m4a"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldNormalURL.path))
    }

    func testUnreadCountTracksNewRecordingsUntilMarkedRead() throws {
        let tempDirectory = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: tempDirectory) }
        let suiteName = "RecordingStoreUnreadTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = RecordingStore(directoryURL: tempDirectory, userDefaults: defaults)
        XCTAssertEqual(store.unreadCount, 0)

        let now = Date()
        let item1 = RecordingItem(fileName: "1.m4a", createdAt: now, duration: 2.0, peakDecibels: -20.0)
        store.add(item1)
        XCTAssertEqual(store.unreadCount, 1)

        store.markAllAsRead(at: now.addingTimeInterval(1))
        XCTAssertEqual(store.unreadCount, 0)

        let item2 = RecordingItem(fileName: "2.m4a", createdAt: now.addingTimeInterval(5), duration: 2.0, peakDecibels: -20.0)
        store.add(item2)
        XCTAssertEqual(store.unreadCount, 1)
    }
}
