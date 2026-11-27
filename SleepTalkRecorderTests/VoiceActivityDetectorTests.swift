import XCTest
@testable import SleepTalkRecorder

final class VoiceActivityDetectorTests: XCTestCase {
    func testRemainsMonitoringBelowThreshold() {
        let settings = RecorderSettings(
            thresholdDecibels: -35.0,
            silenceTimeoutSeconds: 2.0,
            minimumDurationSeconds: 0.5,
            preRollSeconds: 1.0,
            dimScreenDuringMonitoring: true
        )
        var detector = VoiceActivityDetector(settings: settings)

        XCTAssertEqual(detector.process(decibels: -45.0, bufferDuration: 0.1), .none)
        XCTAssertEqual(detector.state, .monitoring)
    }

    func testStartsAndSavesValidSpeech() {
        let settings = RecorderSettings(
            thresholdDecibels: -35.0,
            silenceTimeoutSeconds: 2.0,
            minimumDurationSeconds: 0.6,
            preRollSeconds: 1.0,
            dimScreenDuringMonitoring: true
        )
        var detector = VoiceActivityDetector(settings: settings)

        // 1.0秒分の発話（0.5秒 × 2）
        XCTAssertEqual(detector.process(decibels: -20.0, bufferDuration: 0.5), .startRecording)
        XCTAssertEqual(detector.state, .recording)
        XCTAssertEqual(detector.process(decibels: -15.0, bufferDuration: 0.5), .continueRecording)

        // 1.0秒無音 → まだ継続
        XCTAssertEqual(detector.process(decibels: -50.0, bufferDuration: 1.0), .continueRecording)
        // さらに1.0秒無音 → 合計2.0秒で終了＆保存
        XCTAssertEqual(detector.process(decibels: -50.0, bufferDuration: 1.0), .finishRecording(shouldSave: true))
        XCTAssertEqual(detector.state, .monitoring)
    }

    func testDiscardsShortNoiseBelowMinimumDuration() {
        let settings = RecorderSettings(
            thresholdDecibels: -35.0,
            silenceTimeoutSeconds: 2.0,
            minimumDurationSeconds: 1.0,
            preRollSeconds: 1.0,
            dimScreenDuringMonitoring: true
        )
        var detector = VoiceActivityDetector(settings: settings)

        // 0.2秒だけの単発ノイズ
        XCTAssertEqual(detector.process(decibels: -25.0, bufferDuration: 0.2), .startRecording)
        // 無音2.0秒経過
        XCTAssertEqual(detector.process(decibels: -55.0, bufferDuration: 2.0), .finishRecording(shouldSave: false))
        XCTAssertEqual(detector.state, .monitoring)
    }

    func testSpeechResetsSilenceTimer() {
        let settings = RecorderSettings(
            thresholdDecibels: -35.0,
            silenceTimeoutSeconds: 2.0,
            minimumDurationSeconds: 0.5,
            preRollSeconds: 1.0,
            dimScreenDuringMonitoring: true
        )
        var detector = VoiceActivityDetector(settings: settings)

        XCTAssertEqual(detector.process(decibels: -25.0, bufferDuration: 0.5), .startRecording)
        // 1.5秒無音
        XCTAssertEqual(detector.process(decibels: -50.0, bufferDuration: 1.5), .continueRecording)
        // 再度発話で無音タイマーリセット
        XCTAssertEqual(detector.process(decibels: -20.0, bufferDuration: 0.5), .continueRecording)
        // さらに1.5秒無音でもまだ終了しない
        XCTAssertEqual(detector.process(decibels: -50.0, bufferDuration: 1.5), .continueRecording)
        // 追加0.5秒無音で終了
        XCTAssertEqual(detector.process(decibels: -50.0, bufferDuration: 0.5), .finishRecording(shouldSave: true))
    }

    func testCalculateDecibels() {
        XCTAssertEqual(VoiceActivityDetector.calculateDecibels(samples: []), -160.0)
        XCTAssertEqual(VoiceActivityDetector.calculateDecibels(samples: [0.0, 0.0, 0.0]), -160.0)
        XCTAssertEqual(VoiceActivityDetector.calculateDecibels(samples: [1.0, -1.0, 1.0]), 0.0, accuracy: 0.001)
        XCTAssertEqual(VoiceActivityDetector.calculateDecibels(samples: [0.1, -0.1, 0.1]), -20.0, accuracy: 0.01)
    }

    func testStopsRecordingAtMaxClipDuration() {
        let settings = RecorderSettings(
            thresholdDecibels: -35.0,
            silenceTimeoutSeconds: 3.0,
            minimumDurationSeconds: 0.5,
            preRollSeconds: 1.0,
            dimScreenDuringMonitoring: true,
            maxClipDurationSeconds: 20.0
        )
        var detector = VoiceActivityDetector(settings: settings)

        // エアコン等の定常ノイズが連続しても最大長（20秒）で安全に区切られること
        XCTAssertEqual(detector.process(decibels: -20.0, bufferDuration: 1.0), .startRecording)
        for _ in 0..<18 {
            XCTAssertEqual(detector.process(decibels: -20.0, bufferDuration: 1.0), .continueRecording)
        }
        XCTAssertEqual(detector.process(decibels: -20.0, bufferDuration: 1.0), .finishRecording(shouldSave: true))
        XCTAssertEqual(detector.state, .monitoring)
    }
}
