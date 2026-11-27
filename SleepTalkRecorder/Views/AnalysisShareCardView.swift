import SwiftUI
import UIKit

/// SNSシェア用の「寝言傾向レポートカード」を描画・画像化するビュー
struct AnalysisShareCardView: View {
    static let appStoreURL = URL(string: "https://apps.apple.com/app/id6837623075")!

    let analysis: SleepTalkAnalysis
    let includeKeywords: Bool

    init(analysis: SleepTalkAnalysis, includeKeywords: Bool = false) {
        self.analysis = analysis
        self.includeKeywords = includeKeywords
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.yellow)
                Text("SleepTalk Report")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.9))
                Spacer()
                Text("\(analysis.totalCount) clips")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
            }

            if let primary = analysis.primaryNeed {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Sleep Talk Tendency (Reference)")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.65))

                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(Color.indigo.opacity(0.45))
                                .frame(width: 52, height: 52)
                            Image(systemName: primary.type.symbolName)
                                .font(.title2)
                                .foregroundStyle(.cyan)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(primary.type.localizedTitle)
                                .font(.title3.bold())
                                .foregroundStyle(.white)
                            Text("\(Int((primary.ratio * 100).rounded()))%")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.cyan)
                        }
                    }

                    Text(primary.type.summaryDescription)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }

            if includeKeywords && !analysis.topKeywords.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Frequent Words (Transcribed)")
                        .font(.caption.bold())
                        .foregroundStyle(.white.opacity(0.75))

                    HStack(spacing: 6) {
                        ForEach(analysis.topKeywords.prefix(4)) { item in
                            Text("\(item.word) ×\(item.count)")
                                .font(.caption2.bold())
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.cyan.opacity(0.2), in: Capsule())
                                .foregroundStyle(.cyan)
                        }
                    }
                }
            }

            // 免責表記（エンタメ・セルフリフレクション目的であることを明記）
            Text("For entertainment & self-reflection only. Not a medical diagnosis.")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)

            Divider()
                .overlay(Color.white.opacity(0.15))

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    if let peak = analysis.peakHour {
                        Label("Peak: \(peak):00", systemImage: "clock.fill")
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Text("#SleepTalkReport")
                        .font(.caption2.bold())
                        .foregroundStyle(.cyan.opacity(0.85))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("SleepTalk - Auto Recorder")
                        .font(.caption2.bold())
                        .foregroundStyle(.white.opacity(0.9))
                    Text("Available on App Store")
                        .font(.system(size: 9))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
        .padding(22)
        .frame(width: 360)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.08, blue: 0.18),
                    Color(red: 0.14, green: 0.13, blue: 0.36),
                    Color(red: 0.20, green: 0.16, blue: 0.44)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(Color.white.opacity(0.15), lineWidth: 1)
        )
    }

    /// 診断カードを SNS 共有用の UIImage にレンダリングする
    @MainActor
    static func renderImage(for analysis: SleepTalkAnalysis, includeKeywords: Bool = false) -> UIImage? {
        let renderer = ImageRenderer(
            content: AnalysisShareCardView(analysis: analysis, includeKeywords: includeKeywords)
        )
        renderer.scale = 3.0
        return renderer.uiImage
    }
}
