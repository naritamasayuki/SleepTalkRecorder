import SwiftUI

/// 自動録音パラメータや夜間表示の設定を行う画面
struct SettingsView: View {
    @Bindable var recorder: SleepAudioRecorder

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Detection Threshold")
                            Spacer()
                            Text("\(Int(recorder.settings.thresholdDecibels)) dB")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { Double(recorder.settings.thresholdDecibels) },
                                set: { recorder.settings.thresholdDecibels = Float($0) }
                            ),
                            in: -60...(-10),
                            step: 1
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Silence Timeout")
                            Spacer()
                            Text("\(recorder.settings.silenceTimeoutSeconds, specifier: "%.1f") s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $recorder.settings.silenceTimeoutSeconds,
                            in: 1.0...10.0,
                            step: 0.5
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Minimum Recording Duration")
                            Spacer()
                            Text("\(recorder.settings.minimumDurationSeconds, specifier: "%.1f") s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $recorder.settings.minimumDurationSeconds,
                            in: 0.2...3.0,
                            step: 0.2
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Pre-roll Buffer")
                            Spacer()
                            Text("\(recorder.settings.preRollSeconds, specifier: "%.1f") s")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: $recorder.settings.preRollSeconds,
                            in: 0.0...3.0,
                            step: 0.5
                        )
                    }
                } header: {
                    Text("Voice Detection Settings")
                } footer: {
                    Text("Pre-roll buffering captures audio just before speech triggers so the beginning of sleep talk is not cut off.")
                }

                Section("Display & Naming Settings") {
                    Toggle("Dim Screen on Start (Night Mode)", isOn: $recorder.settings.dimScreenDuringMonitoring)
                    Toggle("Transcribe Sleep Talk for File Name", isOn: $recorder.settings.transcribeForFileName)
                }

                Section("Support & Feedback") {
                    NavigationLink {
                        FeedbackFormView()
                    } label: {
                        Label("Send Feedback or Bug Report", systemImage: "bubble.left.and.exclamationmark.bubble.right.fill")
                    }

                    if let privacyURL = URL(string: "https://naritamasayuki.github.io/SleepTalkRecorder/privacy.html") {
                        Link(destination: privacyURL) {
                            Label("Privacy Policy", systemImage: "hand.raised.fill")
                        }
                    }
                }

                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        recorder.settings = .default
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
