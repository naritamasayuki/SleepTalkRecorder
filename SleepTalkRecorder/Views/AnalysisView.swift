import Charts
import SwiftUI

/// 録音された寝言データの傾向・時間帯分布・音量・頻出ワードを可視化する分析画面
struct AnalysisView: View {
    var store: RecordingStore
    var onStartMonitoringRequested: (() -> Void)?

    @State private var cachedAnalysis: SleepTalkAnalysis = SleepTalkAnalyzer.analyze([])
    @State private var showShareSheet = false

    var body: some View {
        NavigationStack {
            Group {
                if store.recordings.isEmpty {
                    ScrollView {
                        VStack(spacing: 24) {
                            ContentUnavailableView(
                                "No Data to Analyze",
                                systemImage: "chart.bar.xaxis",
                                description: Text("Once sleep talk is recorded, time trends and self-reflection insights will appear here.")
                            )
                            .padding(.top, 28)

                            if let onStartMonitoringRequested {
                                Button {
                                    onStartMonitoringRequested()
                                } label: {
                                    Label("Go to Sleep Monitor", systemImage: "moon.stars.fill")
                                        .font(.headline)
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 14)
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(.indigo)
                                .padding(.horizontal, 24)
                            }
                        }
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            if let primaryNeed = cachedAnalysis.primaryNeed, cachedAnalysis.hasEnoughDataForPsychology {
                                psychologyHeroCard(primaryNeed, allNeeds: cachedAnalysis.psychologicalNeeds)
                            } else {
                                insufficientDataCard(transcribedCount: cachedAnalysis.transcribedCount)
                            }

                            disclaimerBanner
                            summaryGrid(cachedAnalysis)
                            hourlyChartCard(cachedAnalysis)
                            volumeCard(cachedAnalysis)
                            if !cachedAnalysis.topKeywords.isEmpty {
                                keywordsCard(cachedAnalysis)
                            }
                            if !cachedAnalysis.insights.isEmpty {
                                insightsCard(cachedAnalysis)
                            }
                            // 価値を体験したあと（録音データがある場合のみ）に1枠だけ関連グッズを表示
                            SleepGoodsSectionView(psychologicalNeed: cachedAnalysis.primaryNeed?.type)
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Sleep Talk Analysis")
            .toolbar {
                if !store.recordings.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showShareSheet = true
                        } label: {
                            Label("Share Report Card", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareReportPreviewSheet(analysis: cachedAnalysis)
            }
            .task(id: store.recordings) {
                // body評価ごとに再計算せず、recordings変更時のみバックグラウンドで解析してキャッシュする
                let snapshot = store.recordings
                let computed = await Task.detached(priority: .userInitiated) {
                    SleepTalkAnalyzer.analyze(snapshot)
                }.value
                cachedAnalysis = computed
            }
        }
    }

    private var disclaimerBanner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .font(.caption)
                .padding(.top, 2)
            Text("These insights are for entertainment and self-reflection only and have no medical or diagnostic basis.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
    }

    private func insufficientDataCard(transcribedCount: Int) -> some View {
        let required = SleepTalkAnalyzer.minimumTranscribedClipsForPsychology
        return VStack(alignment: .leading, spacing: 10) {
            Label("Collecting More Data", systemImage: "sparkles.rectangle.stack")
                .font(.headline)
                .foregroundStyle(.cyan)
            Text("At least \(required) transcribed sleep-talk clips are needed to show tendency insights (currently \(transcribedCount)/\(required)). Clips without transcribed speech are excluded.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func psychologyHeroCard(_ primary: PsychologicalNeedScore, allNeeds: [PsychologicalNeedScore]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.indigo.opacity(0.3))
                        .frame(width: 48, height: 48)
                    Image(systemName: primary.type.symbolName)
                        .font(.title3)
                        .foregroundStyle(.cyan)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Sleep Talk Tendency (Reference)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(primary.type.localizedTitle)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }

                Spacer()

                Text("\(Int((primary.ratio * 100).rounded()))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(.cyan)
            }

            Text(primary.type.summaryDescription)
                .font(.subheadline)
                .foregroundStyle(.primary.opacity(0.9))

            if !primary.matchedKeywords.isEmpty {
                HStack(spacing: 6) {
                    Text("Keywords:")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    ForEach(primary.matchedKeywords.prefix(4), id: \.self) { word in
                        Text(word)
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.cyan.opacity(0.18), in: Capsule())
                            .foregroundStyle(.cyan)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Keyword Tendency Balance")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                ForEach(allNeeds.prefix(3)) { need in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(need.type.localizedTitle)
                                .font(.caption)
                            Spacer()
                            Text("\(Int((need.ratio * 100).rounded()))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule()
                                    .fill(need.id == primary.id ? Color.cyan : Color.indigo.opacity(0.7))
                                    .frame(width: max(4, geo.size.width * need.ratio))
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
            .padding(.top, 4)

            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                    .font(.caption)
                    .padding(.top, 2)
                Text(primary.type.careAdvice)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding()
        .background(
            LinearGradient(
                colors: [Color.indigo.opacity(0.25), Color.white.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 18)
        )
    }

    private func summaryGrid(_ data: SleepTalkAnalysis) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
            statCard(title: String(localized: "Total Clips"), value: "\(data.totalCount)", icon: "waveform", color: .indigo)
            statCard(title: String(localized: "Total Duration"), value: formatDuration(data.totalDuration), icon: "clock.fill", color: .cyan)
            statCard(title: String(localized: "Avg Duration"), value: String(format: String(localized: "%.1f s"), data.averageDuration), icon: "timer", color: .mint)
            statCard(
                title: String(localized: "Peak Volume"),
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
                Text("Sleep Talk by Hour")
                    .font(.headline)
                Spacer()
                if let peak = data.peakHour {
                    Text("Peak: \(peak):00")
                        .font(.caption.bold())
                        .foregroundStyle(.cyan)
                }
            }

            Chart(data.hourlyBuckets) { bucket in
                BarMark(
                    x: .value("Hour", bucket.hour),
                    y: .value("Count", bucket.count)
                )
                .foregroundStyle(bucket.hour == data.peakHour ? Color.cyan : Color.indigo.opacity(0.8))
                .cornerRadius(3)
            }
            .chartXAxis {
                AxisMarks(values: [0, 3, 6, 9, 12, 15, 18, 21]) { value in
                    AxisGridLine()
                    AxisValueLabel {
                        if let hour = value.as(Int.self) {
                            Text("\(hour)")
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
            Text("Volume Distribution")
                .font(.headline)

            HStack(spacing: 12) {
                volumeBadge(label: String(localized: "Whisper"), sub: "< -30 dB", count: breakdown.quietCount, color: .indigo)
                volumeBadge(label: String(localized: "Normal"), sub: "-30 to -15 dB", count: breakdown.normalCount, color: .cyan)
                volumeBadge(label: String(localized: "Loud"), sub: ">= -15 dB", count: breakdown.loudCount, color: .orange)
            }
        }
        .padding()
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
    }

    private func volumeBadge(label: String, sub: String, count: Int, color: Color) -> some View {
        VStack(spacing: 4) {
            Text("\(count)")
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
            Text("Frequent Words (Transcribed)")
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
            Label("Insights Report", systemImage: "sparkles")
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
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = total >= 60 ? [.minute, .second] : [.second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: TimeInterval(total)) ?? "\(total)s"
    }
}

/// シェア前にカード内容とキーワード表示有無を確認できるプレビューシート
private struct ShareReportPreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let analysis: SleepTalkAnalysis

    @State private var includeKeywords = false
    @State private var renderedImage: UIImage?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    AnalysisShareCardView(analysis: analysis, includeKeywords: includeKeywords)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

                    if !analysis.topKeywords.isEmpty {
                        Toggle("Include Transcribed Keywords", isOn: $includeKeywords)
                            .padding()
                            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    }

                    if let image = renderedImage {
                        ShareLink(
                            item: Image(uiImage: image),
                            message: Text("SleepTalk Report #SleepTalkReport \(AnalysisShareCardView.appStoreURL.absoluteString)"),
                            preview: SharePreview(
                                String(localized: "SleepTalk Report"),
                                image: Image(uiImage: image)
                            )
                        ) {
                            Label("Share Report Card", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.indigo)
                    }
                }
                .padding()
            }
            .navigationTitle("Share Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .onAppear {
                renderedImage = AnalysisShareCardView.renderImage(for: analysis, includeKeywords: includeKeywords)
            }
            .onChange(of: includeKeywords) { _, newValue in
                renderedImage = AnalysisShareCardView.renderImage(for: analysis, includeKeywords: newValue)
            }
        }
        .preferredColorScheme(.dark)
    }
}
