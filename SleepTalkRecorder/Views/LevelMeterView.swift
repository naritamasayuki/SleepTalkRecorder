import SwiftUI

/// 現在の音量（dBFS）と自動録音のしきい値ラインを視覚化するメータービュー
struct LevelMeterView: View {
    let decibels: Float
    let thresholdDecibels: Float
    let isRecording: Bool

    private let minDb: Float = -60.0
    private let maxDb: Float = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("マイク入力レベル")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.1f dB", clampedDb))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isRecording ? .red : .primary)
            }

            GeometryReader { geometry in
                let width = geometry.size.width
                let levelRatio = normalized(clampedDb)
                let thresholdRatio = normalized(thresholdDecibels)

                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white.opacity(0.1))

                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                colors: isRecording
                                    ? [.orange, .red]
                                    : [.indigo, .cyan, .mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, width * levelRatio))
                        .animation(.easeOut(duration: 0.08), value: levelRatio)

                    // しきい値ライン
                    Rectangle()
                        .fill(Color.yellow)
                        .frame(width: 2.5)
                        .offset(x: max(0, min(width - 2.5, width * thresholdRatio)))
                }
            }
            .frame(height: 16)

            HStack {
                Text("-60 dB")
                Spacer()
                Text("しきい値: \(Int(thresholdDecibels)) dB")
                    .foregroundStyle(.yellow)
                Spacer()
                Text("0 dB")
            }
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private var clampedDb: Float {
        min(max(decibels, minDb), maxDb)
    }

    private func normalized(_ db: Float) -> CGFloat {
        let clamped = min(max(db, minDb), maxDb)
        return CGFloat((clamped - minDb) / (maxDb - minDb))
    }
}
