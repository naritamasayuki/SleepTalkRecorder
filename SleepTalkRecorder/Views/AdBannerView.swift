import GoogleMobileAds
import OSLog
import SwiftUI
import UIKit

/// 画面下段に表示する Google AdMob バナー広告ビュー
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

    init(adUnitID: String = AdBannerView.defaultAdUnitID) {
        self.adUnitID = adUnitID
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.12))

            AdMobBannerRepresentable(adUnitID: adUnitID)
                .frame(maxWidth: .infinity)
                .frame(height: Self.bannerHeight)
                .background(Color(white: 0.06))
                .accessibilityLabel(Text("Advertisement Area"))
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
        bannerView.rootViewController = Self.activeRootViewController()
        bannerView.load(Request())
        return bannerView
    }

    func updateUIView(_ uiView: BannerView, context: Context) {
        if uiView.rootViewController == nil {
            uiView.rootViewController = Self.activeRootViewController()
        }
    }

    private static func activeRootViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .rootViewController
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
