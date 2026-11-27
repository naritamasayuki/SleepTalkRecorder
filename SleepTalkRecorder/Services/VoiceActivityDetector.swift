import Foundation

/// 音声レベルに基づく自動録音トリガーの判定アクション
enum DetectorAction: Equatable, Sendable {
    /// 待機状態を維持する
    case none
    /// 音声を検知したため録音を開始する
    case startRecording
    /// 録音状態を維持する
    case continueRecording
    /// 無音が一定時間続いたため録音を終了する（最小録音時間を満たしている場合のみ保存）
    case finishRecording(shouldSave: Bool)
}

/// 音量レベル（dBFS）と時間経過から寝言の開始・終了を判定するステートマシン
struct VoiceActivityDetector: Sendable {
    enum State: Equatable, Sendable {
        case monitoring
        case recording
    }

    private(set) var state: State = .monitoring
    private(set) var recordingDuration: TimeInterval = 0
    private(set) var silenceDuration: TimeInterval = 0
    private(set) var peakDecibels: Float = -160.0

    var settings: RecorderSettings

    init(settings: RecorderSettings = .default) {
        self.settings = settings.clamped()
    }

    /// 現在のバッファの音量（dBFS）と時間長を評価し、次のアクションを返す
    mutating func process(decibels: Float, bufferDuration: TimeInterval) -> DetectorAction {
        let clampedDuration = max(0, bufferDuration)
        let isAboveThreshold = decibels >= settings.thresholdDecibels

        switch state {
        case .monitoring:
            if isAboveThreshold {
                state = .recording
                recordingDuration = clampedDuration
                silenceDuration = 0
                peakDecibels = decibels
                return .startRecording
            }
            return .none

        case .recording:
            recordingDuration += clampedDuration
            if decibels > peakDecibels {
                peakDecibels = decibels
            }

            // 1クリップの最大録音長に達した場合は、エアコンやいびきによる巨大ファイル化を防ぐため区切って保存する
            if recordingDuration >= settings.maxClipDurationSeconds {
                let effectiveSpeechDuration = recordingDuration - silenceDuration
                let shouldSave = effectiveSpeechDuration >= settings.minimumDurationSeconds
                reset()
                return .finishRecording(shouldSave: shouldSave)
            }

            if isAboveThreshold {
                silenceDuration = 0
                return .continueRecording
            } else {
                silenceDuration += clampedDuration
                if silenceDuration >= settings.silenceTimeoutSeconds {
                    let effectiveSpeechDuration = recordingDuration - silenceDuration
                    let shouldSave = effectiveSpeechDuration >= settings.minimumDurationSeconds
                    reset()
                    return .finishRecording(shouldSave: shouldSave)
                }
                return .continueRecording
            }
        }
    }

    /// 状態を初期化する
    mutating func reset() {
        state = .monitoring
        recordingDuration = 0
        silenceDuration = 0
        peakDecibels = -160.0
    }

    /// Float型のPCMサンプル列から実効値ベースの音量（dBFS）を算出する
    static func calculateDecibels(samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return -160.0 }
        var sumOfSquares: Float = 0.0
        for sample in samples {
            sumOfSquares += sample * sample
        }
        let rms = sqrt(sumOfSquares / Float(samples.count))
        guard rms > 0.0 else { return -160.0 }
        let db = 20.0 * log10(rms)
        return min(max(db, -160.0), 0.0)
    }

    /// 配列版の便利オーバーロード（主にテスト用）
    static func calculateDecibels(samples: [Float]) -> Float {
        samples.withUnsafeBufferPointer { buffer in
            calculateDecibels(samples: buffer)
        }
    }
}
