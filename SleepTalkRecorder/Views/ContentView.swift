import SwiftUI

/// アプリ全体のタブナビゲーションと最上位の夜間表示オーバーレイ・広告表示制御を司るルートビュー
struct ContentView: View {
    enum AppTab: Hashable {
        case monitor
        case recordings
        case analysis
        case settings
    }

    var store: RecordingStore
    var recorder: SleepAudioRecorder
    var playbackManager: AudioPlaybackManager
    var consentManager: AdConsentManager

    @State private var selectedTab: AppTab = .monitor
    @State private var isNightDimmed = false

    /// 監視中・カウントダウン中・夜間表示中は寝室で光らないようバナー広告を非表示にする
    private var shouldShowBannerAd: Bool {
        recorder.state == .idle && !isNightDimmed && consentManager.canRequestAds
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabView(selection: $selectedTab) {
                    MonitorView(
                        recorder: recorder,
                        playbackManager: playbackManager,
                        totalRecordingsCount: store.recordings.count,
                        isNightDimmed: $isNightDimmed,
                        onOpenRecordings: {
                            selectedTab = .recordings
                        },
                        onOnboardingCompleted: {
                            Task {
                                await consentManager.requestConsentAndStartAdsIfNeeded()
                            }
                        }
                    )
                    .tag(AppTab.monitor)
                    .tabItem {
                        Label("Monitor", systemImage: "moon.stars.fill")
                    }

                    RecordingsListView(
                        store: store,
                        playbackManager: playbackManager,
                        isMonitoring: recorder.state != .idle
                    )
                    .tag(AppTab.recordings)
                    .tabItem {
                        Label("Recordings", systemImage: "list.bullet.rectangle")
                    }
                    .badge(store.unreadCount)

                    AnalysisView(
                        store: store,
                        onStartMonitoringRequested: {
                            selectedTab = .monitor
                        }
                    )
                    .tag(AppTab.analysis)
                    .tabItem {
                        Label("Analysis", systemImage: "chart.bar.xaxis")
                    }

                    SettingsView(recorder: recorder, consentManager: consentManager)
                        .tag(AppTab.settings)
                        .tabItem {
                            Label("Settings", systemImage: "gearshape.fill")
                        }
                }

                // 同意完了済みかつ待機中のみ、タブバーから余白を空けてバナー広告を表示する
                AdBannerView(canRequestAds: shouldShowBannerAd)
            }

            // 夜間表示オーバーレイを最上位に配置し、タブバーや広告も含めて画面全体を遮光する
            if isNightDimmed && recorder.state != .idle {
                nightDimOverlay
                    .transition(.opacity)
                    .zIndex(100)
            }
        }
        .preferredColorScheme(.dark)
        .tint(.indigo)
    }

    private var nightDimOverlay: some View {
        Color.black
            .ignoresSafeArea()
            .overlay {
                VStack(spacing: 20) {
                    Image(systemName: recorder.state == .recording ? "waveform" : "moon.zzz.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(recorder.state == .recording ? .red.opacity(0.65) : .indigo.opacity(0.45))

                    Text(
                        recorder.state == .recording
                            ? "Recording sleep talk..."
                            : (recorder.state == .countdown ? "Waiting to Start" : "Monitoring overnight")
                    )
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.4))

                    Text("Detected: \(recorder.sessionRecordingCount) clips")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.3))

                    Text("Tap anywhere to return to normal view")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.2))
                        .padding(.top, 24)
                }
            }
            .onTapGesture {
                isNightDimmed = false
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(Text("Tap anywhere to return to normal view"))
    }
}
