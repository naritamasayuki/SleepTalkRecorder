import SwiftUI

/// 自動録音パラメータや夜間表示の設定を行う画面
struct SettingsView: View {
    @Bindable var recorder: SleepAudioRecorder
    @State private var reminderPermissionDenied = false

    private var reminderTimeBinding: Binding<Date> {
        Binding(
            get: {
                var components = DateComponents()
                components.hour = recorder.settings.bedtimeReminderHour
                components.minute = recorder.settings.bedtimeReminderMinute
                return Calendar.current.date(from: components) ?? Date()
            },
            set: { newDate in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                recorder.settings.bedtimeReminderHour = components.hour ?? 23
                recorder.settings.bedtimeReminderMinute = components.minute ?? 0
                if recorder.settings.bedtimeReminderEnabled {
                    Task {
                        let scheduled = await BedtimeReminderManager.scheduleDailyReminder(
                            hour: recorder.settings.bedtimeReminderHour,
                            minute: recorder.settings.bedtimeReminderMinute
                        )
                        reminderPermissionDenied = !scheduled
                    }
                }
            }
        )
    }

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

                Section {
                    Picker("Start Delay Timer", selection: $recorder.settings.startDelayMinutes) {
                        Text("Off").tag(0)
                        Text("15 min").tag(15)
                        Text("30 min").tag(30)
                        Text("45 min").tag(45)
                        Text("60 min").tag(60)
                    }

                    Picker("Auto-Stop Timer", selection: $recorder.settings.autoStopHours) {
                        Text("Off").tag(0)
                        Text("4 hours").tag(4)
                        Text("6 hours").tag(6)
                        Text("8 hours").tag(8)
                        Text("10 hours").tag(10)
                    }
                } header: {
                    Text("Recording Timers")
                } footer: {
                    Text("Use a start delay to skip pre-sleep noise, and auto-stop so recording ends automatically in the morning.")
                }

                Section("Display & Naming Settings") {
                    Toggle("Dim Screen on Start (Night Mode)", isOn: $recorder.settings.dimScreenDuringMonitoring)
                    Toggle("Transcribe Sleep Talk for File Name", isOn: $recorder.settings.transcribeForFileName)
                }

                Section {
                    Toggle(
                        "Daily Bedtime Reminder",
                        isOn: Binding(
                            get: { recorder.settings.bedtimeReminderEnabled },
                            set: { enabled in
                                recorder.settings.bedtimeReminderEnabled = enabled
                                Task {
                                    if enabled {
                                        let scheduled = await BedtimeReminderManager.scheduleDailyReminder(
                                            hour: recorder.settings.bedtimeReminderHour,
                                            minute: recorder.settings.bedtimeReminderMinute
                                        )
                                        if !scheduled {
                                            recorder.settings.bedtimeReminderEnabled = false
                                            reminderPermissionDenied = true
                                        } else {
                                            reminderPermissionDenied = false
                                        }
                                    } else {
                                        BedtimeReminderManager.cancelReminder()
                                        reminderPermissionDenied = false
                                    }
                                }
                            }
                        )
                    )

                    if recorder.settings.bedtimeReminderEnabled {
                        DatePicker(
                            "Reminder Time",
                            selection: reminderTimeBinding,
                            displayedComponents: .hourAndMinute
                        )
                    }

                    if reminderPermissionDenied {
                        Text("Notifications are disabled. Enable them in the Settings app to receive bedtime reminders.")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Bedtime Reminder")
                } footer: {
                    Text("Sends a daily notification so you don't forget to start sleep monitoring before bed.")
                }

                Section("Support & Feedback") {
                    if let goodsURL = AmazonSleepGoodsService.searchURL(for: AmazonSleepGoodsService.recommendations(for: nil)[0]) {
                        Link(destination: goodsURL) {
                            HStack {
                                Label("Browse Sleep Goods on Amazon", systemImage: "bag.fill")
                                Spacer()
                                Text("PR")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

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
                        BedtimeReminderManager.cancelReminder()
                        reminderPermissionDenied = false
                        recorder.settings = .default
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}
