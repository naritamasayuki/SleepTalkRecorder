import Foundation
import OSLog
import Observation

/// 録音された寝言ファイルとメタデータの永続化・管理を行うストア
@MainActor
@Observable
final class RecordingStore {
    private(set) var recordings: [RecordingItem] = []
    var lastErrorMessage: String?

    let directoryURL: URL
    private let metadataURL: URL
    private let fileManager: FileManager
    private let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "RecordingStore")

    init(directoryURL: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
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

    /// 録音アイテムの音声ファイルURLを返す
    func fileURL(for item: RecordingItem) -> URL {
        directoryURL.appendingPathComponent(item.fileName)
    }

    /// 新しい録音アイテムを追加してメタデータを保存する
    func add(_ item: RecordingItem) {
        recordings.insert(item, at: 0)
        saveMetadata()
        logger.info("録音を追加しました: \(item.fileName, privacy: .public) (\(item.duration, format: .fixed(precision: 1))秒)")
    }

    /// 指定された録音アイテムと音声ファイルを削除する
    func delete(_ item: RecordingItem) {
        let url = fileURL(for: item)
        if fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.removeItem(at: url)
            } catch {
                logger.error("音声ファイルの削除に失敗しました: \(error.localizedDescription, privacy: .public)")
                lastErrorMessage = "音声ファイルの削除に失敗しました: \(error.localizedDescription)"
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

    /// メタデータJSONから録音一覧を読み込む
    func load() {
        guard fileManager.fileExists(atPath: metadataURL.path) else {
            recordings = []
            return
        }
        do {
            let data = try Data(contentsOf: metadataURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let decoded = try decoder.decode([RecordingItem].self, from: data)
            // 実ファイルが存在するレコードのみを保持する
            recordings = decoded
                .filter { fileManager.fileExists(atPath: fileURL(for: $0).path) }
                .sorted { $0.createdAt > $1.createdAt }
        } catch {
            logger.error("録音メタデータの読み込みに失敗しました: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = "録音履歴の読み込みに失敗しました。"
            recordings = []
        }
    }

    private func ensureDirectoryExists() {
        guard !fileManager.fileExists(atPath: directoryURL.path) else { return }
        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        } catch {
            logger.error("録音ディレクトリの作成に失敗しました: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = "録音フォルダの作成に失敗しました。"
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
            lastErrorMessage = "録音履歴の保存に失敗しました。"
        }
    }
}
