import Foundation
import NaturalLanguage

/// 寝言データ全体の分析結果を保持するモデル
struct SleepTalkAnalysis: Equatable, Sendable {
    struct HourlyBucket: Identifiable, Equatable, Sendable {
        let hour: Int
        let count: Int
        var id: Int { hour }
    }

    struct KeywordCount: Identifiable, Equatable, Sendable {
        let word: String
        let count: Int
        var id: String { word }
    }

    struct VolumeBreakdown: Equatable, Sendable {
        let quietCount: Int     // -30 dB 未満
        let normalCount: Int    // -30 dB 〜 -15 dB
        let loudCount: Int      // -15 dB 以上

        var total: Int { quietCount + normalCount + loudCount }
    }

    let totalCount: Int
    let totalDuration: TimeInterval
    let averageDuration: TimeInterval
    let maxPeakDecibels: Float?
    let transcribedCount: Int
    let peakHour: Int?
    let hourlyBuckets: [HourlyBucket]
    let topKeywords: [KeywordCount]
    let volumeBreakdown: VolumeBreakdown
    let insights: [String]
}

/// 録音された寝言データから傾向・時間帯分布・頻出キーワードを分析するサービス
enum SleepTalkAnalyzer {
    /// 録音リストを集計・解析して分析結果を返す
    static func analyze(_ items: [RecordingItem], calendar: Calendar = .current) -> SleepTalkAnalysis {
        guard !items.isEmpty else {
            return SleepTalkAnalysis(
                totalCount: 0,
                totalDuration: 0,
                averageDuration: 0,
                maxPeakDecibels: nil,
                transcribedCount: 0,
                peakHour: nil,
                hourlyBuckets: (0..<24).map { SleepTalkAnalysis.HourlyBucket(hour: $0, count: 0) },
                topKeywords: [],
                volumeBreakdown: .init(quietCount: 0, normalCount: 0, loudCount: 0),
                insights: []
            )
        }

        let totalCount = items.count
        let totalDuration = items.reduce(0) { $0 + max(0, $1.duration) }
        let averageDuration = totalDuration / Double(totalCount)
        let maxPeakDecibels = items.map(\.peakDecibels).max()
        let transcribedItems = items.compactMap { item -> String? in
            guard let text = item.transcript?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else {
                return nil
            }
            return text
        }

        // 時間帯別集計（0〜23時）
        var hourCounts = Array(repeating: 0, count: 24)
        for item in items {
            let hour = calendar.component(.hour, from: item.createdAt)
            if (0..<24).contains(hour) {
                hourCounts[hour] += 1
            }
        }
        let hourlyBuckets = (0..<24).map { SleepTalkAnalysis.HourlyBucket(hour: $0, count: hourCounts[$0]) }
        let peakHour = hourlyBuckets.max(by: { $0.count < $1.count })?.hour

        // 音量帯別集計
        var quiet = 0
        var normal = 0
        var loud = 0
        for item in items {
            if item.peakDecibels < -30.0 {
                quiet += 1
            } else if item.peakDecibels < -15.0 {
                normal += 1
            } else {
                loud += 1
            }
        }
        let volumeBreakdown = SleepTalkAnalysis.VolumeBreakdown(
            quietCount: quiet,
            normalCount: normal,
            loudCount: loud
        )

        // 頻出キーワード抽出
        let topKeywords = extractTopKeywords(from: transcribedItems, limit: 8)

        // インサイト文の生成
        let insights = buildInsights(
            totalCount: totalCount,
            averageDuration: averageDuration,
            peakHour: peakHour,
            maxPeakDecibels: maxPeakDecibels,
            volumeBreakdown: volumeBreakdown,
            topKeywords: topKeywords
        )

        return SleepTalkAnalysis(
            totalCount: totalCount,
            totalDuration: totalDuration,
            averageDuration: averageDuration,
            maxPeakDecibels: maxPeakDecibels,
            transcribedCount: transcribedItems.count,
            peakHour: peakHour,
            hourlyBuckets: hourlyBuckets,
            topKeywords: topKeywords,
            volumeBreakdown: volumeBreakdown,
            insights: insights
        )
    }

    /// NaturalLanguage の単語トークナイザを使って日本語キーワードの出現頻度を集計する
    static func extractTopKeywords(from transcripts: [String], limit: Int = 8) -> [SleepTalkAnalysis.KeywordCount] {
        guard !transcripts.isEmpty else { return [] }

        var counts: [String: Int] = [:]
        let tagger = NLTagger(tagSchemes: [.lexicalClass])

        for text in transcripts {
            tagger.string = text
            let range = text.startIndex..<text.endIndex
            let options: NLTagger.Options = [.omitWhitespace, .omitPunctuation, .omitOther]
            tagger.enumerateTags(in: range, unit: .word, scheme: .lexicalClass, options: options) { tag, tokenRange in
                let word = String(text[tokenRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard word.count >= 2 else { return true }
                // 名詞・動詞・形容詞・感動詞を優先して抽出（助詞・助動詞などを除外）
                if let tag, [.noun, .verb, .adjective, .interjection, .otherWord].contains(tag) {
                    counts[word, default: 0] += 1
                } else if tag == nil {
                    counts[word, default: 0] += 1
                }
                return true
            }
        }

        return counts
            .map { SleepTalkAnalysis.KeywordCount(word: $0.key, count: $0.value) }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.word < rhs.word
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    private static func buildInsights(
        totalCount: Int,
        averageDuration: TimeInterval,
        peakHour: Int?,
        maxPeakDecibels: Float?,
        volumeBreakdown: SleepTalkAnalysis.VolumeBreakdown,
        topKeywords: [SleepTalkAnalysis.KeywordCount]
    ) -> [String] {
        var result: [String] = []

        if let peakHour {
            result.append("最も寝言が多い時間帯は \(peakHour)時台 です。")
        }

        if averageDuration < 2.5 {
            result.append(String(format: "平均 %.1f秒 の短い寝言・つぶやきが多い傾向があります。", averageDuration))
        } else {
            result.append(String(format: "平均 %.1f秒 と比較的長めの発話が記録されています。", averageDuration))
        }

        if let maxDb = maxPeakDecibels, volumeBreakdown.loudCount > 0 {
            result.append(String(format: "大きめの寝言（-15 dB以上）が %d件 ありました（最大 %.0f dB）。", volumeBreakdown.loudCount, maxDb))
        } else {
            result.append("全体的に落ち着いた声量（ささやき〜通常レベル）の寝言が中心です。")
        }

        if let top = topKeywords.first {
            result.append("よく記録された言葉は「\(top.word)」です（\(top.count)回）。")
        }

        return result
    }
}
