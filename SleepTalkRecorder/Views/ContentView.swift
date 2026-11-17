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
                MonitorView(recorder: recorder, playbackManager: playbackManager)
                    .tabItem {
                        Label("モニター", systemImage: "moon.stars.fill")
                    }

                RecordingsListView(
                    store: store,
                    playbackManager: playbackManager,
                    isMonitoring: recorder.state != .idle
                )
                .tabItem {
                    Label("録音履歴", systemImage: "list.bullet.rectangle")
                }
                .badge(store.recordings.count)

                SettingsView(recorder: recorder)
                    .tabItem {
                        Label("設定", systemImage: "gearshape.fill")
                    }
            }

            // 全タブ共通の下段バナー広告領域
            AdBannerView()
        }
        .preferredColorScheme(.dark)
        .tint(.indigo)
    }
}
