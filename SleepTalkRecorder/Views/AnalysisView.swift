import Charts
import SwiftUI

/// 録音された寝言データの時間帯分布・傾向・頻出ワードを可視化する分析画面
struct AnalysisView: View {
    var store: RecordingStore

    private var analysis: SleepTalkAnalysis {
        SleepTalkAnalyzer.analyze(store.recordings)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.recordings.isEmpty {
                    ContentUnavailableView(
                        "分析するデータがまだありません",
                        systemImage: "chart.bar.xaxis",
                        description: Text("寝言が録音されると、時間帯の傾向やよく言った言葉がここに表示されます。")
                    )
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            summaryGrid(analysis)
                            hourlyChartCard(analysis)
                            volumeCard(analysis)
                            if !analysis.topKeywords.isEmpty {
                                keywordsCard(analysis)
                            }
                            insightsCard(analysis)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("寝言分析")
        }
    }

    private func summaryGrid(_ data: SleepTalkAnalysis) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: "総録音回数", value: "\(data.totalCount) 件", icon: "waveform", color: .indigo)
            statCard(title: "合計時間", value: formatDuration(data.totalDuration), icon: "clock.fill", color: .cyan)
            statCard(title: "平均の長さ", value: String(format: "%.1f 秒", data.averageDuration), icon: "timer", color: .mint)
            statCard(
                title: "最大音量",
                value: data.maxPeakDecibels.map { String(format: "%.0f dB", $0) } ?? "--",
                icon: "speaker.wave.3.fill",
                color: .orange
            )
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
    }

    private func hourlyChartCard(_ data: SleepTalkAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("時間帯別の寝言回数")
                    .font(.headline)
                Spacer()
                if let peak = data.peakHour {
                    Text("ピーク: \(peak)時台")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                }
            }

            Chart(data.hourlyBuckets) { bucket in
                BarMark(
                    x: .value("時", bucket.hour),
                    y: .value("回数", bucket.count)
                )
                .foregroundStyle(bucket.hour == data.peakHour ? Color.cyan : Color.indigo.opacity(0.8))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text("\(hour)時")
                                .font(.caption2)
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 180)
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func volumeCard(_ data: SleepTalkAnalysis) -> some View {
        let breakdown = data.volumeBreakdown
        return VStack(alignment: .leading, spacing: 12) {
            Text("声の大きさの傾向")
                .font(.headline)

            HStack(spacing: 12) {
                volumeBadge(label: "ささやき", sub: "< -30 dB", count: breakdown.quietCount, color: .indigo)
                volumeBadge(label: "ふつう", sub: "-30〜-15 dB", count: breakdown.normalCount, color: .cyan)
                volumeBadge(label: "大きめ", sub: ">= -15 dB", count: breakdown.loudCount, color: .orange)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func volumeBadge(label: String, sub: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count) 件")
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(label)
                .font(.caption.bold())
            Text(sub)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func keywordsCard(_ data: SleepTalkAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("よく出た言葉（文字起こし分析）")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(data.topKeywords) { item in
                    HStack(spacing: 4) {
                        Text(item.word)
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                        Text("×\(item.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.cyan)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.indigo.opacity(0.25), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func insightsCard(_ data: SleepTalkAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("分析レポート", systemImage: "sparkles")
                .font(.headline)
                .foregroundStyle(.yellow)

            ForEach(data.insights, id: \.self) { insight in
                HStack(alignment: .top, spacing: 8) {
                    Text("•")
                        .foregroundStyle(.cyan)
                    Text(insight)
                        .font(.subheadline)
                        .foregroundStyle(.primary.opacity(0.9))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        let minutes = total / 60
        let secs = total % 60
        if minutes > 0 {
            return "\(minutes)分\(secs)秒"
        }
        return "\(secs)秒"
    }
}
