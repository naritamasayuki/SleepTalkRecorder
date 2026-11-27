import AppTrackingTransparency
import GoogleMobileAds
import OSLog
import Observation
import SwiftUI
import UIKit
import UserMessagingPlatform

/// UMP（欧州・英国向け同意管理）→ ATT → AdMob SDK 初期化の順序を制御するマネージャー
@MainActor
@Observable
final class AdConsentManager {
    private(set) var canRequestAds: Bool = false
    private var hasRequestedConsent = false
    private var hasStartedSDK = false
    private let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "AdConsentManager")

    /// オンボーディング完了後に UMP 同意確認 → ATT → AdMob SDK 開始の順で実行する
    func requestConsentAndStartAdsIfNeeded() async {
        guard !hasRequestedConsent else { return }
        hasRequestedConsent = true

        // 1. UMP 同意情報の更新（EEA/UK では同意フォームを提示）
        let parameters = RequestParameters()
        do {
            try await ConsentInformation.shared.requestConsentInfoUpdate(with: parameters)
            if let rootVC = Self.activeRootViewController() {
                try await ConsentForm.loadAndPresentIfRequired(from: rootVC)
            }
        } catch {
            logger.warning("UMP同意フォームの処理でエラーが発生しました: \(error.localizedDescription, privacy: .public)")
        }

        // 2. UMP 同意確認後に ATT ダイアログを表示（未回答の場合のみ）
        if ATTrackingManager.trackingAuthorizationStatus == .notDetermined {
            _ = await ATTrackingManager.requestTrackingAuthorization()
        }

        // 3. 同意状態が広告リクエスト可能であれば AdMob SDK を初期化する
        let allowed = ConsentInformation.shared.canRequestAds
        canRequestAds = allowed
        if allowed {
            await startMobileAdsIfNeeded()
        } else {
            logger.info("同意状態により広告リクエストを保留しています")
        }
    }

    private func startMobileAdsIfNeeded() async {
        guard !hasStartedSDK else { return }
        hasStartedSDK = true
        await MobileAds.shared.start()
        logger.info("Google Mobile Ads SDK の初期化が完了しました")
    }

    static func activeRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
    }
}

/// 画面下段に表示する Google AdMob バナー広告ビュー（同意完了後のみ読み込む）
struct AdBannerView: View {
    /// 標準バナー広告の高さ（320x50）
    static let bannerHeight: CGFloat = 50

    /// 開発時（DEBUG）はGoogle公式テストIDを使用し、本番（Release）で本番広告ユニットIDを使用する
    static var defaultAdUnitID: String {
        #if DEBUG
        "ca-app-pub-3940256099942544/2934735716"
        #else
        "ca-app-pub-4261439423960578/1149348877"
        #endif
    }

    let adUnitID: String
    let canRequestAds: Bool

    init(adUnitID: String = AdBannerView.defaultAdUnitID, canRequestAds: Bool = true) {
        self.adUnitID = adUnitID
        self.canRequestAds = canRequestAds
    }

    var body: some View {
        if canRequestAds {
            VStack(spacing: 0) {
                // タブバーとの誤タップ防止のため余白と区切りを設ける
                Spacer()
                    .frame(height: 8)
                Divider()
                    .overlay(Color.white.opacity(0.14))

                AdMobBannerRepresentable(adUnitID: adUnitID)
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.bannerHeight)
                    .background(Color(white: 0.06))
                    .accessibilityLabel(Text("Advertisement Area"))
            }
            .background(Color.black)
        }
    }
}

/// Google Mobile Ads SDK の BannerView を SwiftUI から表示するラッパー
private struct AdMobBannerRepresentable: UIViewRepresentable {
    let adUnitID: String

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> BannerView {
        let bannerView = BannerView(adSize: AdSizeBanner)
        bannerView.adUnitID = adUnitID
        bannerView.delegate = context.coordinator
        bannerView.rootViewController = AdConsentManager.activeRootViewController()
        bannerView.load(Request())
        return bannerView
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        if uiView.rootViewController == nil {
            uiView.rootViewController = AdConsentManager.activeRootViewController()
        }
    }

    final class Coordinator: NSObject, BannerViewDelegate {
        private let logger = Logger(subsystem: "com.sleeptalkrecorder.app", category: "AdBannerView")

        func bannerViewDidReceiveAd(_ bannerView: BannerView) {
            logger.debug("AdMobバナー広告の読み込みに成功しました")
        }

        func bannerView(_ bannerView: BannerView, didFailToReceiveAdWithError error: Error) {
            logger.warning("AdMobバナー広告の読み込みに失敗しました: \(error.localizedDescription, privacy: .public)")
        }
    }
}
