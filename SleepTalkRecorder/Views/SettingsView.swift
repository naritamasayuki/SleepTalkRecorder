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
                            Text("検知しきい値")
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
                            Text("無音終了までの待機時間")
                            Spacer()
                            Text(String(format: "%.1f 秒", recorder.settings.silenceTimeoutSeconds))
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
                            Text("最小録音時間（ノイズ除外）")
                            Spacer()
                            Text(String(format: "%.1f 秒", recorder.settings.minimumDurationSeconds))
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
                            Text("プリロール録音（さかのぼり）")
                            Spacer()
                            Text(String(format: "%.1f 秒", recorder.settings.preRollSeconds))
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
                    Text("音声検知設定")
                } footer: {
                    Text("プリロール録音を有効にすると、寝言の話し始めが途切れずに保存されます。")
                }

                Section("表示・ファイル名設定") {
                    Toggle("開始時に画面を暗くする（夜間モード）", isOn: $recorder.settings.dimScreenDuringMonitoring)
                    Toggle("寝言を文字起こししてファイル名にする", isOn: $recorder.settings.transcribeForFileName)
                }

                Section {
                    Button("初期設定に戻す", role: .destructive) {
                        recorder.settings = .default
                    }
                }
            }
            .navigationTitle("設定")
        }
    }
}
