import Foundation
import OSLog
import Speech

/// SFSpeechRecognizer を用いて録音ファイルの内容を文字起こしし、ファイル名を生成するサービス
enum SpeechTranscriber {
    private static let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "SpeechTranscriber")

    /// 現在の音声認識権限ステータスを返す
    static var authorizationStatus: SFSpeechRecognizerAuthorizationStatus {
        SFSpeechRecognizer.authorizationStatus()
    }

    /// 音声認識権限をリクエストする
    static func requestAuthorizationIfNeeded() async -> SFSpeechRecognizerAuthorizationStatus {
        let current = SFSpeechRecognizer.authorizationStatus()
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    /// 端末のロケール（未対応時は英語にフォールバック）に応じた音声認識ロケールを返す
    static func resolvedLocale(for preferredLocale: Locale = .autoupdatingCurrent) -> Locale {
        let supported = SFSpeechRecognizer.supportedLocales()
        if supported.contains(preferredLocale) {
            return preferredLocale
        }
        if let languageCode = preferredLocale.language.languageCode?.identifier,
           let matched = supported.first(where: { $0.language.languageCode?.identifier == languageCode }) {
            return matched
        }
        return Locale(identifier: "en-US")
    }

    /// 音声ファイルを端末の言語設定に合わせて文字起こしし、認識されたテキストを返す（認識不可・エラー時は nil）
    /// - Parameters:
    ///   - fileURL: 文字起こし対象の音声ファイルURL
    ///   - locale: 音声認識ロケール
    ///   - allowServerRecognition: オンデバイス認識が利用できない場合にAppleサーバー認識を許可するか（既定: false）
    static func transcribe(
        fileURL: URL,
        locale: Locale = .autoupdatingCurrent,
        allowServerRecognition: Bool = false
    ) async -> String? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        let targetLocale = resolvedLocale(for: locale)
        guard let recognizer = SFSpeechRecognizer(locale: targetLocale) ?? SFSpeechRecognizer(locale: Locale(identifier: "en-US")),
              recognizer.isAvailable else {
            logger.warning("音声認識エンジンが利用できないため文字起こしをスキップします")
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false

        if recognizer.supportsOnDeviceRecognition {
            // オンデバイス認識に対応している場合は、明示的にサーバー認識を許可していない限り端末内で完結させる
            request.requiresOnDeviceRecognition = !allowServerRecognition
        } else if allowServerRecognition {
            request.requiresOnDeviceRecognition = false
        } else {
            logger.info("オンデバイス音声認識が利用できず、サーバー認識も無効のため文字起こしをスキップします")
            return nil
        }

        return await withCheckedContinuation { continuation in
            let box = RecognitionContinuationBox(continuation: continuation)
            let task = recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    logger.info("文字起こしを完了できませんでした: \(error.localizedDescription, privacy: .public)")
                    box.finish(with: nil)
                    return
                }

                if let result, result.isFinal {
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    box.finish(with: text.isEmpty ? nil : text)
                }
            }
            box.attach(task: task, timeoutSeconds: 15.0)
        }
    }

    /// 音声認識コールバックとタイムアウトをスレッドセーフに1回だけ解決するボックス
    private final class RecognitionContinuationBox: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<String?, Never>?
        private var task: SFSpeechRecognitionTask?
        private var isFinished = false

        init(continuation: CheckedContinuation<String?, Never>) {
            self.continuation = continuation
        }

        func attach(task: SFSpeechRecognitionTask, timeoutSeconds: TimeInterval) {
            lock.lock()
            if isFinished {
                lock.unlock()
                task.cancel()
                return
            }
            self.task = task
            lock.unlock()

            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeoutSeconds) { [weak self] in
                self?.finish(with: nil)
            }
        }

        func finish(with value: String?) {
            lock.lock()
            guard !isFinished else {
                lock.unlock()
                return
            }
            isFinished = true
            let cont = continuation
            let runningTask = task
            continuation = nil
            task = nil
            lock.unlock()

            if value == nil {
                runningTask?.cancel()
            }
            cont?.resume(returning: value)
        }
    }

    /// 文字起こしテキストを iOS ファイルシステムで安全なファイル名ベース（拡張子なし）に変換する
    static func sanitizeFileName(_ text: String, maxLength: Int = 24) -> String? {
        let forbidden = CharacterSet(charactersIn: "/\\:*?\"<>|\r\n\t")
        let cleanedScalars = text.unicodeScalars.map { scalar -> Character in
            forbidden.contains(scalar) ? " " : Character(scalar)
        }
        let normalized = String(cleanedScalars)
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "._"))

        guard !normalized.isEmpty else { return nil }
        let limited = String(normalized.prefix(max(1, maxLength)))
            .trimmingCharacters(in: CharacterSet(charactersIn: "._"))
        return limited.isEmpty ? nil : limited
    }
}
