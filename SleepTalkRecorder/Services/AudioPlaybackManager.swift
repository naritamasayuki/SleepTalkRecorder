import AVFoundation
import Foundation
import OSLog
import Observation

/// 録音済み音声ファイルの再生を管理するクラス
@MainActor
@Observable
final class AudioPlaybackManager: NSObject, AVAudioPlayerDelegate {
    private(set) var currentPlayingID: UUID?
    private(set) var isPlaying: Bool = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var errorMessage: String?

    private var player: AVAudioPlayer?
    private var progressTimer: Timer?
    private let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "AudioPlaybackManager")

    /// 指定した録音アイテムを再生または一時停止する
    func togglePlayback(for item: RecordingItem, fileURL: URL) {
        if currentPlayingID == item.id {
            if isPlaying {
                pause()
            } else {
                resume()
            }
            return
        }
        startPlayback(for: item, fileURL: fileURL)
    }

    /// 再生を開始する
    func startPlayback(for item: RecordingItem, fileURL: URL) {
        stop()

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            errorMessage = String(localized: "Audio file could not be found.")
            logger.error("再生対象ファイルが存在しません: \(fileURL.path, privacy: .public)")
            return
        }

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default)
            try session.setActive(true)

            let audioPlayer = try AVAudioPlayer(contentsOf: fileURL)
            audioPlayer.delegate = self
            audioPlayer.prepareToPlay()

            guard audioPlayer.play() else {
                errorMessage = String(localized: "Unable to start audio playback.")
                logger.error("AVAudioPlayer.play() が false を返しました")
                return
            }

            player = audioPlayer
            currentPlayingID = item.id
            duration = audioPlayer.duration
            currentTime = 0
            isPlaying = true
            startTimer()
        } catch {
            errorMessage = String(localized: "Failed to play audio: \(error.localizedDescription)")
            logger.error("再生初期化エラー: \(error.localizedDescription, privacy: .public)")
            stop()
        }
    }

    /// 再生を一時停止する
    func pause() {
        player?.pause()
        isPlaying = false
        stopTimer()
    }

    /// 一時停止中の再生を再開する
    func resume() {
        guard let player else { return }
        if player.play() {
            isPlaying = true
            startTimer()
        }
    }

    /// 再生位置を指定秒数にシークする
    func seek(to time: TimeInterval) {
        guard let player else { return }
        let clamped = min(max(0, time), player.duration)
        player.currentTime = clamped
        currentTime = clamped
    }

    /// 再生を完全に停止してリソースを解放する
    func stop() {
        stopTimer()
        player?.stop()
        player = nil
        currentPlayingID = nil
        isPlaying = false
        currentTime = 0
        duration = 0
    }

    private func startTimer() {
        stopTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, let player = self.player else { return }
                self.currentTime = player.currentTime
            }
        }
    }

    private func stopTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    // MARK: - AVAudioPlayerDelegate

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            self?.stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: (any Error)?) {
        Task { @MainActor [weak self] in
            let message = error?.localizedDescription ?? "Unknown decode error"
            self?.logger.error("再生デコードエラー: \(message, privacy: .public)")
            self?.errorMessage = String(localized: "An error occurred while playing the audio file.")
            self?.stop()
        }
    }
}
