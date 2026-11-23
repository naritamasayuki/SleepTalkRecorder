import SwiftUI
import UIKit

/// SNSシェア用の「深層心理診断カード」を描画・画像化するビュー
struct AnalysisShareCardView: View {
    let analysis: SleepTalkAnalysis

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.yellow)
                Text("SleepTalk Psychology Report")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text("\(analysis.totalCount) clips")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.cyan)
            }

            if let primary = analysis.primaryNeed {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Subconscious Need (Estimated)")
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

            if !analysis.topKeywords.isEmpty {
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

            HStack {
                if let peak = analysis.peakHour {
                    Label("Peak: \(peak):00", systemImage: "clock.fill")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                Text("SleepTalk")
                    .font(.caption.bold())
                    .foregroundStyle(.indigo.opacity(0.9))
            }
            .padding(.top, 4)
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
    static func renderImage(for analysis: SleepTalkAnalysis) -> UIImage? {
        let renderer = ImageRenderer(content: AnalysisShareCardView(analysis: analysis))
        renderer.scale = 3.0
        return renderer.uiImage
    }
}
