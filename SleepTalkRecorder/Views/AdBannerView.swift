import SwiftUI

/// 画面下段に表示するバナー広告領域ビュー
/// 本番運用時は Google Mobile Ads SDK (GADBannerView) などの UIViewRepresentable に差し替えて利用する
struct AdBannerView: View {
    /// 標準バナー広告の高さ（320x50）
    static let bannerHeight: CGFloat = 50

    /// テスト用・本番用の広告ユニットID（AdMob テストバナーIDを既定値に設定）
    let adUnitID: String

    init(adUnitID: String = "ca-app-pub-3940256099942544/2934735716") {
        self.adUnitID = adUnitID
    }

    var body: some View {
        // 本番（Release）ビルドで実広告SDKが未導入の場合は、App Store審査ガイドライン2.1対策として枠を非表示にする
        #if DEBUG
        bannerContent
        #else
        EmptyView()
        #endif
    }

    private var bannerContent: some View {
        VStack(spacing: 0) {
            Divider()
                .overlay(Color.white.opacity(0.12))

            ZStack {
                Color(white: 0.08)

                HStack(spacing: 8) {
                    Text("AD")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.white.opacity(0.15), in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)

                    Text("Ad Space (Banner 320×50)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.bannerHeight)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("Advertisement Area"))
        }
    }
}
