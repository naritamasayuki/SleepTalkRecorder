import SwiftUI
import UIKit

/// 睡眠中の自動録音待機・状態表示・マイクテスト・朝サマリーを扱うメインモニター画面
struct MonitorView: View {
    @Bindable var recorder: SleepAudioRecorder
    var playbackManager: AudioPlaybackManager
    var totalRecordingsCount: Int
    @Binding var isNightDimmed: Bool
    var onOpenRecordings: () -> Void
    var onOnboardingCompleted: () -> Void

    @AppStorage("com.sleeptalkrecorder.hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var showOnboarding = false
    @State private var calibrationBannerMessage: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        statusHeader
                        if recorder.state == .countdown, let endTime = recorder.countdownEndTime {
                            countdownCard(until: endTime)
                        }
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
                } else if recorder.state == .idle {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showOnboarding = true
                        } label: {
                            Label("Setup Guide", systemImage: "questionmark.circle")
                        }
                    }
                }
            }
            .onAppear {
                if !hasCompletedOnboarding {
                    showOnboarding = true
                }
            }
            .onDisappear {
                if recorder.isMicTesting {
                    recorder.stopMicTest()
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
            .sheet(isPresented: $showOnboarding, onDismiss: {
                if recorder.isMicTesting {
                    recorder.stopMicTest()
                }
                if !hasCompletedOnboarding {
                    hasCompletedOnboarding = true
                }
                onOnboardingCompleted()
            }) {
                OnboardingSheet(recorder: recorder) {
                    hasCompletedOnboarding = true
                    showOnboarding = false
                }
            }
            .sheet(
                item: Binding(
                    get: {
                        recorder.pendingSessionSummary.map { IdentifiableSessionSummary(summary: $0) }
                    },
                    set: { newValue in
                        if newValue == nil {
                            recorder.dismissPendingSessionSummary()
                        }
                    }
                )
            ) { wrapper in
                MorningSummarySheet(
                    summary: wrapper.summary,
                    recorder: recorder,
                    onViewRecordings: {
                        recorder.dismissPendingSessionSummary()
                        onOpenRecordings()
                    },
                    onClose: {
                        recorder.dismissPendingSessionSummary()
                    }
                )
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
                    .symbolEffect(.pulse, isActive: recorder.state == .recording || recorder.isMicTesting)
            }

            Text(statusTitle)
                .font(.title2.bold())

            Text(statusSubtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
    }

    private func countdownCard(until endTime: Date) -> some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                let remaining = max(0, Int(endTime.timeIntervalSince(context.date).rounded(.up)))
                Text(String(format: "%02d:%02d", remaining / 60, remaining % 60))
                    .font(.system(size: 36, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.yellow)
            }

            Button {
                recorder.skipCountdownAndStartNow()
            } label: {
                Label("Start Now", systemImage: "play.fill")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.borderedProminent)
            .tint(.indigo)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private var sessionStatsCard: some View {
        VStack(spacing: 10) {
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

            if let autoStop = recorder.autoStopDate, recorder.state == .monitoring || recorder.state == .recording {
                let stopTimeText = autoStop.formatted(date: .omitted, time: .shortened)
                Label("Auto-stop at \(stopTimeText)", systemImage: "timer")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
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

            if recorder.state == .idle {
                HStack(spacing: 10) {
                    Button {
                        if recorder.isMicTesting {
                            recorder.stopMicTest()
                        } else {
                            playbackManager.stop()
                            Task { _ = await recorder.startMicTest() }
                        }
                    } label: {
                        Label(
                            recorder.isMicTesting ? "Stop Test" : "Mic Test",
                            systemImage: recorder.isMicTesting ? "stop.circle.fill" : "waveform"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(recorder.isMicTesting ? .orange : .cyan)

                    Button {
                        playbackManager.stop()
                        calibrationBannerMessage = nil
                        Task {
                            if let recommended = await recorder.calibrateAmbientNoise(durationSeconds: 5.0) {
                                calibrationBannerMessage = String(localized: "Recommended threshold set to \(Int(recommended)) dB.")
                            }
                        }
                    } label: {
                        if recorder.isCalibratingNoiseFloor {
                            HStack(spacing: 6) {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Measuring...")
                            }
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                        } else {
                            Label("Auto-Calibrate (5s)", systemImage: "wand.and.stars")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                    .disabled(recorder.isCalibratingNoiseFloor)
                }

                if let msg = calibrationBannerMessage {
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.mint)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
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
                recorder.stopMonitoring()
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

    private var statusColor: Color {
        if recorder.isMicTesting { return .mint }
        switch recorder.state {
        case .idle: return .indigo
        case .countdown: return .yellow
        case .monitoring: return .cyan
        case .recording: return .red
        case .interrupted: return .orange
        }
    }

    private var statusIconName: String {
        if recorder.isMicTesting { return "waveform.badge.mic" }
        switch recorder.state {
        case .idle: return "moon.zzz"
        case .countdown: return "timer"
        case .monitoring: return "ear.and.waveform"
        case .recording: return "mic.fill"
        case .interrupted: return "pause.circle.fill"
        }
    }

    private var statusTitle: String {
        if recorder.isMicTesting {
            return String(localized: "Mic Test Active")
        }
        switch recorder.state {
        case .idle:
            return String(localized: "Standby")
        case .countdown:
            return String(localized: "Waiting to Start")
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
        if recorder.isMicTesting {
            return String(localized: "Speak or stay quiet to check the meter and tune the yellow threshold line.")
        }
        switch recorder.state {
        case .idle:
            return String(localized: "Tap the button before sleeping to automatically record only sleep talk.")
        case .countdown:
            return String(localized: "Recording will begin automatically once the start delay finishes.")
        case .monitoring:
            return String(localized: "Recording starts automatically when sound exceeds the threshold.")
        case .recording:
            return String(localized: "Recording stops and saves automatically after silence.")
        case .interrupted:
            return String(localized: "Paused due to a phone call or alarm. Attempting automatic resume...")
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

private struct IdentifiableSessionSummary: Identifiable {
    let id = UUID()
    let summary: SessionSummary
}

/// 朝のセッション結果サマリーシート（手動・自動停止の両方に対応、中断履歴＆リマインダー提案付き）
private struct MorningSummarySheet: View {
    let summary: SessionSummary
    @Bindable var recorder: SleepAudioRecorder
    let onViewRecordings: () -> Void
    let onClose: () -> Void

    @State private var reminderScheduledMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: summary.detectedCount > 0 ? "sun.max.fill" : "moon.stars.fill")
                        .font(.system(size: 54))
                        .foregroundStyle(summary.detectedCount > 0 ? .yellow : .indigo)
                        .padding(.top, 12)

                    Text("Good Morning!")
                        .font(.title.bold())

                    VStack(spacing: 8) {
                        Text("\(summary.detectedCount) clips")
                            .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.cyan)
                        Text(
                            "\(summary.startedAt.formatted(date: .omitted, time: .shortened)) - \(summary.endedAt.formatted(date: .omitted, time: .shortened))"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                        if summary.endedAutomatically {
                            Text("Ended automatically by timer")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    if summary.endedDueToLowStorage {
                        Label(
                            "Stopped early because device storage was running low.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if !summary.interruptions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Interruptions During Session", systemImage: "pause.circle.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.orange)
                            ForEach(summary.interruptions) { item in
                                let startText = item.beganAt.formatted(date: .omitted, time: .shortened)
                                let endText = item.endedAt?.formatted(date: .omitted, time: .shortened) ?? "--"
                                Text("• \(startText) – \(endText)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
                    }

                    // リマインダー未設定の場合は毎晩の継続を促すワンタップ提案を表示
                    if !recorder.settings.bedtimeReminderEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Don't Forget Tomorrow Night", systemImage: "bell.badge.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(.yellow)
                            Text("Enable a daily bedtime reminder so you never miss recording your sleep talk.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Button {
                                Task {
                                    let scheduled = await BedtimeReminderManager.scheduleDailyReminder(
                                        hour: recorder.settings.bedtimeReminderHour,
                                        minute: recorder.settings.bedtimeReminderMinute
                                    )
                                    if scheduled {
                                        recorder.settings.bedtimeReminderEnabled = true
                                        reminderScheduledMessage = String(localized: "Daily bedtime reminder enabled!")
                                    } else {
                                        reminderScheduledMessage = String(localized: "Notifications are disabled in system Settings.")
                                    }
                                }
                            } label: {
                                Label("Enable Daily Reminder (23:00)", systemImage: "bell.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(.yellow)

                            if let msg = reminderScheduledMessage {
                                Text(msg)
                                    .font(.caption2)
                                    .foregroundStyle(.mint)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                    }

                    VStack(spacing: 12) {
                        if summary.detectedCount > 0 {
                            Button {
                                onViewRecordings()
                            } label: {
                                Label("Listen to Recordings", systemImage: "play.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.indigo)
                        }

                        Button("Close") {
                            onClose()
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                }
                .padding()
            }
            .navigationTitle("Session Summary")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }
}

/// 初回起動時に価値説明と5秒マイクテスト（しきい値自動調整）を行うオンボーディングシート
private struct OnboardingSheet: View {
    @Bindable var recorder: SleepAudioRecorder
    let onFinish: () -> Void

    @State private var calibrationMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "moon.stars.fill")
                        .font(.system(size: 56))
                        .foregroundStyle(.cyan)
                        .padding(.top, 16)

                    VStack(spacing: 8) {
                        Text("Welcome to SleepTalk")
                            .font(.title2.bold())
                        Text("Automatically records only your sleep talk overnight while skipping hours of silence.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        onboardingStep(
                            icon: "mic.fill",
                            color: .cyan,
                            title: String(localized: "1. Test Your Room Volume"),
                            detail: String(localized: "Measure 5 seconds of quiet room noise so the app sets the ideal threshold automatically.")
                        )
                        onboardingStep(
                            icon: "lock.fill",
                            color: .indigo,
                            title: String(localized: "2. Lock Screen & Sleep"),
                            detail: String(localized: "Plug in your charger, start monitoring, and lock your screen. Recordings stay privately on your iPhone.")
                        )
                        onboardingStep(
                            icon: "sparkles",
                            color: .yellow,
                            title: String(localized: "3. Check Your Morning Report"),
                            detail: String(localized: "Listen to clips, view transcriptions, and explore fun self-reflection insights.")
                        )
                    }
                    .padding()
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    VStack(spacing: 12) {
                        LevelMeterView(
                            decibels: recorder.currentDecibels,
                            thresholdDecibels: recorder.settings.thresholdDecibels,
                            isRecording: false
                        )

                        Button {
                            calibrationMessage = nil
                            Task {
                                if let recommended = await recorder.calibrateAmbientNoise(durationSeconds: 5.0) {
                                    calibrationMessage = String(localized: "Ideal threshold set to \(Int(recommended)) dB!")
                                }
                            }
                        } label: {
                            if recorder.isCalibratingNoiseFloor {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Measuring room silence (5s)...")
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                            } else {
                                Label("Run 5-Second Mic Calibration", systemImage: "wand.and.stars")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.cyan)
                        .disabled(recorder.isCalibratingNoiseFloor)

                        if let calibrationMessage {
                            Text(calibrationMessage)
                                .font(.caption)
                                .foregroundStyle(.mint)
                        }
                    }
                    .padding()
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))

                    Button {
                        if recorder.isMicTesting {
                            recorder.stopMicTest()
                        }
                        onFinish()
                    } label: {
                        Text("Get Started")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.indigo)
                }
                .padding()
            }
            .navigationTitle("Quick Setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Skip") {
                        if recorder.isMicTesting {
                            recorder.stopMicTest()
                        }
                        onFinish()
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func onboardingStep(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
