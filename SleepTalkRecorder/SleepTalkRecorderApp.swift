import AppTrackingTransparency
import GoogleMobileAds
import SwiftUI

/// 寝言自動録音アプリのエントリーポイント
@main
struct SleepTalkRecorderApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @State private var hasInitializedAds = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onChange(of: scenePhase) { _, newPhase in
                    guard newPhase == .active, !hasInitializedAds else { return }
                    hasInitializedAds = true
                    Task {
                        // アプリが完全に前面表示されてからATTダイアログを表示し、その後にAdMobを初期化する
                        try? await Task.sleep(for: .milliseconds(600))
                        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
                            _ = await ATTrackingManager.requestTrackingAuthorization()
                        }
                        await MobileAds.shared.start()
                    }
                }
        }
    }
}
