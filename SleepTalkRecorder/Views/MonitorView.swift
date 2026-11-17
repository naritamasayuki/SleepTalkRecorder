import SwiftUI
import UIKit

/// 睡眠中の自動録音待機・状態表示・制御を行うメインモニター画面
struct MonitorView: View {
    @Bindable var recorder: SleepAudioRecorder
    var playbackManager: AudioPlaybackManager
    @State private var isNightDimmed = false

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
                        controlButton
                    }
                    .padding()
                }

                if isNightDimmed && recorder.state != .idle {
                    nightDimOverlay
                }
            }
            .navigationTitle("おやすみモニター")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if recorder.state != .idle && recorder.settings.dimScreenDuringMonitoring {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            isNightDimmed = true
                        } label: {
                            Label("夜間表示", systemImage: "moon.fill")
                        }
                    }
                }
            }
            .alert(
                "エラー",
                isPresented: Binding(
                    get: { recorder.errorMessage != nil },
                    set: { if !$0 { recorder.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(recorder.errorMessage ?? "")
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
                Text("監視時間")
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
                Text("検知した寝言")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("\(recorder.sessionRecordingCount) 件")
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
                    Text("検知しきい値")
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

                Text("環境音に反応しないよう、黄色のラインを普段の静かな音量より少し高めに設定してください。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private var permissionDeniedCard: some View {
        VStack(spacing: 10) {
            Label("マイクへのアクセスが必要です", systemImage: "mic.slash.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text("「設定」アプリからマイク権限を許可すると、睡眠中の寝言を自動録音できます。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("設定アプリを開く") {
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
                recorder.stopMonitoring()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: recorder.state == .idle ? "moon.stars.fill" : "stop.fill")
                Text(recorder.state == .idle ? "おやすみ録音を開始" : "モニタリングを停止")
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

                    Text(recorder.state == .recording ? "寝言を録音中..." : "おやすみ監視中")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.5))

                    Text("検知件数: \(recorder.sessionRecordingCount) 件")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.35))

                    Text("画面をタップして通常表示に戻る")
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
        case .idle: return "待機中"
        case .monitoring: return "音声を監視中"
        case .recording: return String(format: "寝言を録音中 (%.1f秒)", recorder.currentClipDuration)
        case .interrupted: return "一時中断中"
        }
    }

    private var statusSubtitle: String {
        switch recorder.state {
        case .idle: return "就寝前にボタンを押すと、寝言だけを自動で録音します。"
        case .monitoring: return "しきい値を超える音声を検知すると自動で録音が始まります。"
        case .recording: return "無音が続くと自動で録音を保存して待機に戻ります。"
        case .interrupted: return "電話やアラームなどにより一時停止しています。"
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
