import StoreKit
import SwiftUI
import UIKit

/// 睡眠中の自動録音待機・状態表示・制御を行うメインモニター画面
struct MonitorView: View {
    @Environment(\.requestReview) private var requestReview

    @Bindable var recorder: SleepAudioRecorder
    var playbackManager: AudioPlaybackManager
    var totalRecordingsCount: Int
    @State private var isNightDimmed = false
    @State private var sessionSummaryCount: Int?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        statusHeader
                        sessionStatsCard
                        meterAndThresholdCard
                        if recorder.permissionState == .denied {
                            permissionDeniedCard
                        }
                        chargingTipBanner
                        controlButton
                    }
                    .padding()
                }

                if isNightDimmed && recorder.state != .idle {
                    nightDimOverlay
                }
            }
            .navigationTitle("Sleep Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if recorder.state != .idle && recorder.settings.dimScreenDuringMonitoring {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isNightDimmed = true
                        } label: {
                            Label("Night Display", systemImage: "moon.fill")
                        }
                    }
                }
            }
            .alert(
                "Error",
                isPresented: Binding(
                    get: { recorder.errorMessage != nil },
                    set: { if !$0 { recorder.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recorder.errorMessage ?? "")
            }
            .alert(
                "Good Morning!",
                isPresented: Binding(
                    get: { sessionSummaryCount != nil },
                    set: { if !$0 { sessionSummaryCount = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    if ReviewPromptManager.shouldRequestReview(totalRecordingsCount: totalRecordingsCount) {
                        ReviewPromptManager.markPromptShown()
                        requestReview()
                    }
                }
            } message: {
                if let count = sessionSummaryCount {
                    Text("Detected \(count) sleep-talk clip(s) during this session. Check the Recordings and Analysis tabs!")
                }
            }
            .onChange(of: recorder.state) { _, newState in
                if newState == .idle {
                    isNightDimmed = false
                }
            }
        }
    }

    private var statusHeader: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.18))
                    .frame(width: 112, height: 112)

                Image(systemName: statusIconName)
                    .font(.system(size: 44))
                    .foregroundStyle(statusColor)
                    .symbolEffect(.pulse, isActive: recorder.state == .recording)
            }

            Text(statusTitle)
                .font(.title2.bold())

            Text(statusSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
    }

    private var sessionStatsCard: some View {
        HStack(spacing: 16) {
            VStack(spacing: 4) {
                Text("Elapsed Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let startTime = recorder.sessionStartTime, recorder.state != .idle {
                    TimelineView(.periodic(from: .now, by: 1.0)) { context in
                        Text(formatElapsed(from: startTime, to: context.date))
                            .font(.title3.monospacedDigit().bold())
                    }
                } else {
                    Text("00:00:00")
                        .font(.title3.monospacedDigit().bold())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)

            Divider()
                .frame(height: 36)

            VStack(spacing: 4) {
                Text("Detected Clips")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(recorder.sessionRecordingCount) clips")
                    .font(.title3.monospacedDigit().bold())
                    .foregroundStyle(recorder.sessionRecordingCount > 0 ? .cyan : .primary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var meterAndThresholdCard: some View {
        VStack(spacing: 16) {
            LevelMeterView(
                decibels: recorder.currentDecibels,
                thresholdDecibels: recorder.settings.thresholdDecibels,
                isRecording: recorder.state == .recording
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Detection Threshold")
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int(recorder.settings.thresholdDecibels)) dB")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.yellow)
                }
                Slider(
                    value: Binding(
                        get: { Double(recorder.settings.thresholdDecibels) },
                        set: { recorder.settings.thresholdDecibels = Float($0) }
                    ),
                    in: -60...(-10),
                    step: 1
                )
                .tint(.yellow)

                Text("Set the yellow line slightly above your room's quiet ambient noise level.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var permissionDeniedCard: some View {
        VStack(spacing: 10) {
            Label("Microphone Access Required", systemImage: "mic.slash.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("Allow microphone access in Settings to automatically record sleep talk.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
    }

    private var chargingTipBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "battery.100.bolt")
                .font(.title3)
                .foregroundStyle(.green)

            Text("Charging is recommended. Keep your device plugged in for overnight monitoring (works while screen is locked).")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private var controlButton: some View {
        Button {
            if recorder.state == .idle {
                playbackManager.stop()
                Task {
                    await recorder.startMonitoring()
                    if recorder.state != .idle && recorder.settings.dimScreenDuringMonitoring {
                        isNightDimmed = true
                    }
                }
            } else {
                let recordedCount = recorder.sessionRecordingCount
                recorder.stopMonitoring()
                if recordedCount > 0 {
                    sessionSummaryCount = recordedCount
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recorder.state == .idle ? "moon.stars.fill" : "stop.fill")
                Text(recorder.state == .idle ? "Start Sleep Recording" : "Stop Monitoring")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(recorder.state == .idle ? Color.indigo : Color.red.opacity(0.85))
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .padding(.top, 4)
    }

    private var nightDimOverlay: some View {
        Color.black.opacity(0.92)
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    Image(systemName: recorder.state == .recording ? "waveform" : "moon.zzz.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(recorder.state == .recording ? .red.opacity(0.75) : .indigo.opacity(0.6))

                    Text(recorder.state == .recording ? "Recording sleep talk..." : "Monitoring overnight")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.5))

                    Text("Detected: \(recorder.sessionRecordingCount) clips")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))

                    Text("Tap anywhere to return to normal view")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.25))
                        .padding(.top, 24)
                }
            }
            .onTapGesture {
                isNightDimmed = false
            }
    }

    private var statusColor: Color {
        switch recorder.state {
        case .idle: return .indigo
        case .monitoring: return .cyan
        case .recording: return .red
        case .interrupted: return .orange
        }
    }

    private var statusIconName: String {
        switch recorder.state {
        case .idle: return "moon.zzz"
        case .monitoring: return "ear.and.waveform"
        case .recording: return "mic.fill"
        case .interrupted: return "pause.circle.fill"
        }
    }

    private var statusTitle: String {
        switch recorder.state {
        case .idle:
            return String(localized: "Standby")
        case .monitoring:
            return String(localized: "Monitoring Audio")
        case .recording:
            let durationText = String(format: "%.1f", recorder.currentClipDuration)
            return String(localized: "Recording (\(durationText)s)")
        case .interrupted:
            return String(localized: "Interrupted")
        }
    }

    private var statusSubtitle: String {
        switch recorder.state {
        case .idle:
            return String(localized: "Tap the button before sleeping to automatically record only sleep talk.")
        case .monitoring:
            return String(localized: "Recording starts automatically when sound exceeds the threshold.")
        case .recording:
            return String(localized: "Recording stops and saves automatically after silence.")
        case .interrupted:
            return String(localized: "Paused due to a phone call or alarm.")
        }
    }

    private func formatElapsed(from start: Date, to end: Date) -> String {
        let total = max(0, Int(end.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }
}
