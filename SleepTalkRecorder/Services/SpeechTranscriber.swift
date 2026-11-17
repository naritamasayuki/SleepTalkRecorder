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

    /// 音声ファイルを日本語で文字起こしし、認識されたテキストを返す（認識不可・エラー時は nil）
    static func transcribe(fileURL: URL) async -> String? {
        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            return nil
        }
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "ja-JP")),
              recognizer.isAvailable else {
            logger.warning("音声認識エンジンが利用できないため文字起こしをスキップします")
            return nil
        }

        let request = SFSpeechURLRecognitionRequest(url: fileURL)
        request.shouldReportPartialResults = false
        // オンデバイス認識に対応している場合はオフラインでも実行できるようにする
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        return await withCheckedContinuation { continuation in
            var hasResumed = false
            var task: SFSpeechRecognitionTask?
            task = recognizer.recognitionTask(with: request) { result, error in
                guard !hasResumed else { return }

                if let error {
                    hasResumed = true
                    logger.info("文字起こしを完了できませんでした: \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: nil)
                    task?.cancel()
                    return
                }

                if let result, result.isFinal {
                    hasResumed = true
                    let text = result.bestTranscription.formattedString
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: text.isEmpty ? nil : text)
                }
            }
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
