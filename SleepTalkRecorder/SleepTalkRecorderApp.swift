import AppIntents
import SwiftUI

/// アプリ全体で単一のストア・レコーダー・広告同意マネージャーを共有するコンテナ（マルチシーン重複を防止）
@MainActor
final class AppDependencies {
    static let shared = AppDependencies()

    let store: RecordingStore
    let recorder: SleepAudioRecorder
    let playbackManager: AudioPlaybackManager
    let consentManager: AdConsentManager

    private init() {
        let store = RecordingStore()
        self.store = store
        self.recorder = SleepAudioRecorder(store: store)
        self.playbackManager = AudioPlaybackManager()
        self.consentManager = AdConsentManager()
    }
}

/// ショートカット・Siri・「睡眠」集中モードのオートメーションから寝言録音を開始する App Intent
struct StartSleepMonitoringIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Sleep Recording"
    static let description = IntentDescription("Starts automatic sleep talk monitoring.")
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult {
        let deps = AppDependencies.shared
        deps.playbackManager.stop()
        await deps.recorder.startMonitoring()
        return .result()
    }
}

/// ショートカット・Siri から寝言録音を停止する App Intent
struct StopSleepMonitoringIntent: AppIntent {
    static let title: LocalizedStringResource = "Stop Sleep Recording"
    static let description = IntentDescription("Stops automatic sleep talk monitoring.")
    static let openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        AppDependencies.shared.recorder.stopMonitoring()
        return .result()
    }
}

/// Siri / ショートカットアプリに提案されるショートカット定義
struct SleepTalkShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSleepMonitoringIntent(),
            phrases: [
                "Start sleep recording in \(.applicationName)"
            ],
            shortTitle: "Start Sleep Recording",
            systemImageName: "moon.stars.fill"
        )
        AppShortcut(
            intent: StopSleepMonitoringIntent(),
            phrases: [
                "Stop sleep recording in \(.applicationName)"
            ],
            shortTitle: "Stop Sleep Recording",
            systemImageName: "stop.fill"
        )
    }
}

/// 寝言自動録音アプリのエントリーポイント
@main
struct SleepTalkRecorderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("com.sleeptalkrecorder.hasCompletedOnboarding") private var hasCompletedOnboarding = false

    private let dependencies = AppDependencies.shared

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: dependencies.store,
                recorder: dependencies.recorder,
                playbackManager: dependencies.playbackManager,
                consentManager: dependencies.consentManager
            )
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, hasCompletedOnboarding else { return }
                Task {
                    // オンボーディング済みのユーザーのみ、前面表示後に UMP → ATT → AdMob を初期化する
                    try? await Task.sleep(for: .milliseconds(500))
                    await dependencies.consentManager.requestConsentAndStartAdsIfNeeded()
                }
            }
        }
    }
}
