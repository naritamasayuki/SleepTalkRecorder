import AVFoundation
import Foundation
import OSLog
import Observation

/// 1件だけ壊れた要素があっても配列全体のデコード失敗を防ぐためのラッパー
private struct FailableDecodable<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(T.self)
    }
}

/// 録音された寝言ファイルとメタデータの永続化・管理を行うストア
@MainActor
@Observable
final class RecordingStore {
    private(set) var recordings: [RecordingItem] = []
    private(set) var unreadCount: Int = 0
    var lastErrorMessage: String?

    let directoryURL: URL
    private let metadataURL: URL
    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let lastViewedKey = "com.sleeptalkrecorder.recordingsLastViewedAt"
    private let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "RecordingStore")

    init(
        directoryURL: URL? = nil,
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults
        if let directoryURL {
            self.directoryURL = directoryURL
        } else {
            let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            self.directoryURL = docs.appendingPathComponent("Recordings", isDirectory: true)
        }
        self.metadataURL = self.directoryURL.appendingPathComponent("recordings.json")
        ensureDirectoryExists()
        load()
    }

    /// 録音履歴タブを閲覧済みとしてマークし、未読バッジをリセットする
    func markAllAsRead(at date: Date = Date()) {
        userDefaults.set(date.timeIntervalSince1970, forKey: lastViewedKey)
        unreadCount = 0
    }

    private func recomputeUnreadCount() {
        let lastViewedTs = userDefaults.double(forKey: lastViewedKey)
        guard lastViewedTs > 0 else {
            unreadCount = recordings.count
            return
        }
        let lastViewedDate = Date(timeIntervalSince1970: lastViewedTs)
        unreadCount = recordings.filter { $0.createdAt > lastViewedDate }.count
    }

    /// 録音アイテムの音声ファイルURLを返す
    func fileURL(for item: RecordingItem) -> URL {
        directoryURL.appendingPathComponent(item.fileName)
    }

    /// 新しい録音アイテムを追加してメタデータを保存する
    func add(_ item: RecordingItem) {
        recordings.insert(item, at: 0)
        recomputeUnreadCount()
        saveMetadata()
        logger.info("録音を追加しました: \(item.fileName, privacy: .private) (\(item.duration, format: .fixed(precision: 1))秒)")
    }

    /// 文字起こし結果をもとに音声ファイル名とメタデータを更新する
    func updateTranscript(for itemID: UUID, transcript: String) {
        guard let index = recordings.firstIndex(where: { $0.id == itemID }) else { return }
        var item = recordings[index]
        item.transcript = transcript

        if let sanitizedBase = SpeechTranscriber.sanitizeFileName(transcript) {
            let currentURL = fileURL(for: item)
            let pathExtension = currentURL.pathExtension.isEmpty ? "m4a" : currentURL.pathExtension
            let uniqueName = makeUniqueFileName(base: sanitizedBase, ext: pathExtension, excluding: item.fileName)
            let destinationURL = directoryURL.appendingPathComponent(uniqueName)

            if currentURL != destinationURL, fileManager.fileExists(atPath: currentURL.path) {
                do {
                    try fileManager.moveItem(at: currentURL, to: destinationURL)
                    item.fileName = uniqueName
                    logger.info("寝言内容でファイル名を変更しました: \(uniqueName, privacy: .private)")
                } catch {
                    logger.error("ファイル名変更に失敗しました: \(error.localizedDescription, privacy: .public)")
                }
            }
        }

        recordings[index] = item
        saveMetadata()
    }

    private func makeUniqueFileName(base: String, ext: String, excluding currentName: String) -> String {
        let initial = "\(base).\(ext)"
        if initial == currentName || !fileManager.fileExists(atPath: directoryURL.appendingPathComponent(initial).path) {
            return initial
        }
        var suffix = 2
        while true {
            let candidate = "\(base)_\(suffix).\(ext)"
            if candidate == currentName || !fileManager.fileExists(atPath: directoryURL.appendingPathComponent(candidate).path) {
                return candidate
            }
            suffix += 1
        }
    }

    /// 指定された録音アイテムと音声ファイルを削除する
    func delete(_ item: RecordingItem) {
        let url = fileURL(for: item)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                logger.error("音声ファイルの削除に失敗しました: \(error.localizedDescription, privacy: .public)")
                lastErrorMessage = String(localized: "Failed to delete audio file: \(error.localizedDescription)")
            }
        }
        recordings.removeAll { $0.id == item.id }
        saveMetadata()
    }

    /// インデックス集合を指定して録音アイテムを一括削除する
    func delete(at offsets: IndexSet) {
        let targets = offsets.compactMap { index in
            recordings.indices.contains(index) ? recordings[index] : nil
        }
        for item in targets {
            delete(item)
        }
    }

    /// 指定された録音アイテムのお気に入り状態をトグルする
    func toggleFavorite(for itemID: UUID) {
        guard let index = recordings.firstIndex(where: { $0.id == itemID }) else { return }
        recordings[index].isFavorite.toggle()
        saveMetadata()
    }

    /// お気に入り以外の録音アイテムと音声ファイルを一括削除する
    func deleteNonFavorites() {
        let targets = recordings.filter { !$0.isFavorite }
        for item in targets {
            let url = fileURL(for: item)
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    logger.error("音声ファイル削除エラー: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        recordings.removeAll { !$0.isFavorite }
        recomputeUnreadCount()
        saveMetadata()
    }

    /// 指定日数より古いお気に入り以外の録音を削除し、削除件数を返す
    @discardableResult
    func deleteNonFavorites(olderThanDays days: Int, now: Date = Date()) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = now.addingTimeInterval(-TimeInterval(days) * 24 * 60 * 60)
        let targets = recordings.filter { !$0.isFavorite && $0.createdAt < cutoff }
        for item in targets {
            let url = fileURL(for: item)
            if fileManager.fileExists(atPath: url.path) {
                try? fileManager.removeItem(at: url)
            }
        }
        guard !targets.isEmpty else { return 0 }
        let ids = Set(targets.map(\.id))
        recordings.removeAll { ids.contains($0.id) }
        recomputeUnreadCount()
        saveMetadata()
        logger.info("\(days)日以上経過した非お気に入り録音を \(targets.count) 件自動削除しました")
        return targets.count
    }

    /// 録音アイテムを日付ごと（新しい順）にグルーピングする
    static func groupedByDay(
        _ items: [RecordingItem],
        calendar: Calendar = .current
    ) -> [(day: Date, items: [RecordingItem])] {
        let grouped = Dictionary(grouping: items) { item in
            calendar.startOfDay(for: item.createdAt)
        }
        return grouped
            .map { day, dayItems in
                (day: day, items: dayItems.sorted { $0.createdAt > $1.createdAt })
            }
            .sorted { $0.day > $1.day }
    }

    /// すべての録音アイテムと音声ファイルを削除する
    func deleteAll() {
        for item in recordings {
            let url = fileURL(for: item)
            if fileManager.fileExists(atPath: url.path) {
                do {
                    try fileManager.removeItem(at: url)
                } catch {
                    logger.error("音声ファイル削除エラー: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        recordings.removeAll()
        saveMetadata()
    }

    /// メタデータJSONから録音一覧を読み込み、破損耐性・孤立m4a復元を行う
    func load() {
        var loadedItems: [RecordingItem] = []
        var needsResave = false

        if fileManager.fileExists(atPath: metadataURL.path) {
            do {
                let data = try Data(contentsOf: metadataURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let failableList = try decoder.decode([FailableDecodable<RecordingItem>].self, from: data)
                let valid = failableList.compactMap(\.value)
                if valid.count < failableList.count {
                    logger.warning("破損した録音メタデータ要素を \(failableList.count - valid.count) 件スキップしました")
                    lastErrorMessage = String(localized: "Some corrupted entries in recording history were skipped and recovered.")
                    needsResave = true
                }
                loadedItems = valid.filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
            } catch {
                logger.error("録音メタデータの読み込みに失敗しました: \(error.localizedDescription, privacy: .public)")
                backupCorruptedMetadata()
                lastErrorMessage = String(localized: "Recording history file was corrupted and backed up. Existing audio files were recovered automatically.")
                loadedItems = []
                needsResave = true
            }
        }

        // ディレクトリ内の .m4a を走査し、メタデータに存在しない孤立ファイルを復元する
        let recovered = recoverOrphanedAudioFiles(existing: loadedItems)
        if !recovered.isEmpty {
            loadedItems.append(contentsOf: recovered)
            needsResave = true
            logger.info("メタデータ未登録の音声ファイルを \(recovered.count) 件復元しました")
        }

        recordings = loadedItems.sorted { $0.createdAt > $1.createdAt }
        recomputeUnreadCount()

        if needsResave {
            saveMetadata()
        }
    }

    /// 破損した recordings.json を recordings.corrupt.json へ退避する
    private func backupCorruptedMetadata() {
        let backupURL = directoryURL.appendingPathComponent("recordings.corrupt.json")
        do {
            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }
            try fileManager.copyItem(at: metadataURL, to: backupURL)
            logger.info("破損したメタデータを recordings.corrupt.json に退避しました")
        } catch {
            logger.error("破損メタデータの退避に失敗しました: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// ディレクトリ内に残っている .m4a のうちメタデータに未登録のものを復元する
    private func recoverOrphanedAudioFiles(existing: [RecordingItem]) -> [RecordingItem] {
        let registeredNames = Set(existing.map(\.fileName))
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var recovered: [RecordingItem] = []
        for url in contents where url.pathExtension.lowercased() == "m4a" {
            let name = url.lastPathComponent
            guard !registeredNames.contains(name) else { continue }

            let resourceValues = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
            let createdAt = resourceValues?.creationDate ?? resourceValues?.contentModificationDate ?? Date()
            guard let duration = readAudioDuration(at: url) else {
                logger.warning("再生できない孤立音声ファイルを復元対象から除外しました")
                continue
            }
            let item = RecordingItem(
                fileName: name,
                createdAt: createdAt,
                duration: duration,
                peakDecibels: -30.0
            )
            recovered.append(item)
        }
        return recovered
    }

    private func readAudioDuration(at url: URL) -> TimeInterval? {
        guard let audioFile = try? AVAudioFile(forReading: url),
              audioFile.processingFormat.sampleRate > 0,
              audioFile.length > 0 else {
            return nil
        }
        let seconds = Double(audioFile.length) / audioFile.processingFormat.sampleRate
        return max(0.1, seconds)
    }

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            logger.error("録音ディレクトリの作成に失敗しました: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = String(localized: "Failed to create recordings folder.")
        }
    }

    private func saveMetadata() {
        ensureDirectoryExists()
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(recordings)
            try data.write(to: metadataURL, options: [.atomic])
        } catch {
            logger.error("録音メタデータの保存に失敗しました: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = String(localized: "Failed to save recording history.")
        }
    }
}
