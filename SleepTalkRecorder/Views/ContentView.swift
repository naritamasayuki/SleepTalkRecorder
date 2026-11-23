import SwiftUI

/// アプリ全体のタブナビゲーションと主要サービスを保持するルートビュー
struct ContentView: View {
    @State private var store: RecordingStore
    @State private var recorder: SleepAudioRecorder
    @State private var playbackManager: AudioPlaybackManager

    init() {
        let store = RecordingStore()
        _store = State(initialValue: store)
        _recorder = State(initialValue: SleepAudioRecorder(store: store))
        _playbackManager = State(initialValue: AudioPlaybackManager())
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                MonitorView(
                    recorder: recorder,
                    playbackManager: playbackManager,
                    totalRecordingsCount: store.recordings.count
                )
                .tabItem {
                    Label("Monitor", systemImage: "moon.stars.fill")
                }

                RecordingsListView(
                    store: store,
                    playbackManager: playbackManager,
                    isMonitoring: recorder.state != .idle
                )
                .tabItem {
                    Label("Recordings", systemImage: "list.bullet.rectangle")
                }
                .badge(store.recordings.count)

                AnalysisView(store: store)
                    .tabItem {
                        Label("Analysis", systemImage: "chart.bar.xaxis")
                    }

                SettingsView(recorder: recorder)
                    .tabItem {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
            }

            // 全タブ共通の下段バナー広告領域
            AdBannerView()
        }
        .preferredColorScheme(.dark)
        .tint(.indigo)
    }
}
