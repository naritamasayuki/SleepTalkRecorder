import SwiftUI

/// 安眠グッズのAmazonアソシエイトリンクを表示するおすすめカードセクション（PR表記付き）
struct SleepGoodsSectionView: View {
    let psychologicalNeed: PsychologicalNeedType?

    private var items: [SleepGoodRecommendation] {
        AmazonSleepGoodsService.recommendations(for: psychologicalNeed)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Label("Recommended Sleep Goods", systemImage: "bag.fill")
                    .font(.headline)
                    .foregroundStyle(.white)

                Text("PR")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(.orange)

                Spacer()
            }

            Text("Helpful items tailored to your sleep condition (opens Amazon).")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(spacing: 10) {
                ForEach(items) { item in
                    if let url = AmazonSleepGoodsService.searchURL(for: item) {
                        Link(destination: url) {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.indigo.opacity(0.25))
                                        .frame(width: 40, height: 40)
                                    Image(systemName: item.symbolName)
                                        .foregroundStyle(.cyan)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }

                                Spacer()

                                Image(systemName: "arrow.up.right.square")
                                    .font(.subheadline)
                                    .foregroundStyle(.orange)
                            }
                            .padding(10)
                            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }
}
