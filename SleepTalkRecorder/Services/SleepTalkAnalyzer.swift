import Foundation
import NaturalLanguage

/// 寝言データから推定される深層心理の要求カテゴリ
enum PsychologicalNeedType: String, CaseIterable, Identifiable, Sendable {
    case rest = "休息・回復の要求"
    case relief = "緊張からの解放要求"
    case connection = "承認・つながりの要求"
    case safety = "安心・安全の要求"
    case freedom = "自由・楽しみの要求"
    case clarity = "思考・記憶の整理"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .rest: return "bed.double.fill"
        case .relief: return "wind"
        case .connection: return "heart.fill"
        case .safety: return "shield.lefthalf.filled"
        case .freedom: return "sparkles"
        case .clarity: return "brain.head.profile"
        }
    }

    var summaryDescription: String {
        switch self {
        case .rest:
            return "心身が十分な睡眠とリラックスを強く求めています。疲労が蓄積しているサインかもしれません。"
        case .relief:
            return "日中の責任感や「やらなければ」という緊張から解放されたいという無意識の表れです。"
        case .connection:
            return "誰かに気持ちを分かってもらいたい、つながりや共感を得たいという要求が隠れています。"
        case .safety:
            return "小さな不安やストレスを感じており、心から安心できる落ち着いた環境を求めています。"
        case .freedom:
            return "日常の枠から離れて、楽しさや新しい刺激・開放感を味わいたいという欲求が高まっています。"
        case .clarity:
            return "日中の出来事や思考を、脳が睡眠中に静かに整理・定着させている安定した状態です。"
        }
    }

    var careAdvice: String {
        switch self {
        case .rest:
            return "今夜はいつもより30分早く照明を落とし、体を温めて深い休息をとるのがおすすめです。"
        case .relief:
            return "寝る前に気になっているタスクを紙に書き出して頭から切り離すと、緊張が和らぎます。"
        case .connection:
            return "信頼できる人や家族と少し会話したり、安心できる音楽を聴いてから眠ると心が満たされます。"
        case .safety:
            return "部屋の温度や寝具を整え、深呼吸を数回行って安心感を感じながら眠りにつきましょう。"
        case .freedom:
            return "週末に少しだけ普段と違う場所へ出かけたり、好きな趣味の時間を確保してみてください。"
        case .clarity:
            return "現在の睡眠リズムは良好です。このまま規則正しい就寝時間を保ちましょう。"
        }
    }
}

/// 個別の深層心理ニーズのスコア結果
struct PsychologicalNeedScore: Identifiable, Equatable, Sendable {
    let type: PsychologicalNeedType
    let score: Double
    let ratio: Double
    let matchedKeywords: [String]

    var id: String { type.rawValue }
}

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
    let psychologicalNeeds: [PsychologicalNeedScore]
    let primaryNeed: PsychologicalNeedScore?
    let insights: [String]
}

/// 録音された寝言データから深層心理の要求・傾向・時間帯分布を分析するサービス
enum SleepTalkAnalyzer {
    private static let keywordDictionary: [PsychologicalNeedType: [String]] = [
        .rest: ["眠い", "寝", "疲れ", "休み", "休みたい", "しんどい", "だるい", "無理", "帰りたい", "もう", "重い"],
        .relief: ["仕事", "明日", "時間", "遅刻", "やらなきゃ", "ダメ", "急いで", "確認", "終わらない", "お金", "会社", "学校"],
        .connection: ["ありがとう", "ごめん", "好き", "一緒", "寂しい", "誰", "待って", "聞いて", "電話", "会いたい"],
        .safety: ["怖い", "やめ", "助けて", "痛い", "暗い", "落ちる", "危ない", "嫌", "逃げ", "どこ", "違う"],
        .freedom: ["行きたい", "欲しい", "食べる", "美味しい", "旅行", "海", "空", "楽しい", "遊ぶ", "自由", "買い"]
    ]

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
                psychologicalNeeds: [],
                primaryNeed: nil,
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

        // 深層心理の要求分析
        let psychologicalNeeds = analyzePsychologicalNeeds(items: items, calendar: calendar)
        let primaryNeed = psychologicalNeeds.first

        // インサイト文の生成
        let insights = buildInsights(
            averageDuration: averageDuration,
            peakHour: peakHour,
            maxPeakDecibels: maxPeakDecibels,
            volumeBreakdown: volumeBreakdown,
            topKeywords: topKeywords,
            primaryNeed: primaryNeed
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
            psychologicalNeeds: psychologicalNeeds,
            primaryNeed: primaryNeed,
            insights: insights
        )
    }

    /// 文字起こし内容と発話パターン（音量・長さ・時間帯）から深層心理の要求をスコアリングする
    static func analyzePsychologicalNeeds(
        items: [RecordingItem],
        calendar: Calendar = .current
    ) -> [PsychologicalNeedScore] {
        guard !items.isEmpty else { return [] }

        var scores: [PsychologicalNeedType: Double] = Dictionary(
            uniqueKeysWithValues: PsychologicalNeedType.allCases.map { ($0, 0.0) }
        )
        var matchedMap: [PsychologicalNeedType: Set<String>] = [:]

        for item in items {
            let hour = calendar.component(.hour, from: item.createdAt)

            // 1. 音響特徴・時間帯によるベーススコア
            if item.peakDecibels < -30.0 {
                scores[.rest, default: 0] += 1.2
                scores[.clarity, default: 0] += 0.8
            } else if item.peakDecibels >= -15.0 {
                scores[.relief, default: 0] += 1.2
                scores[.safety, default: 0] += 1.0
            } else {
                scores[.connection, default: 0] += 1.0
                scores[.clarity, default: 0] += 0.6
            }

            if item.duration >= 3.5 {
                scores[.connection, default: 0] += 0.8
            } else {
                scores[.clarity, default: 0] += 0.5
            }

            if (2...4).contains(hour) {
                scores[.rest, default: 0] += 0.6
            } else if (5...7).contains(hour) {
                scores[.relief, default: 0] += 0.7
            }

            // 2. 文字起こしキーワードによる重み付け（心理的意味が最も強い指標）
            if let transcript = item.transcript, !transcript.isEmpty {
                for (needType, keywords) in keywordDictionary {
                    for keyword in keywords where transcript.localizedCaseInsensitiveContains(keyword) {
                        scores[needType, default: 0] += 3.0
                        matchedMap[needType, default: []].insert(keyword)
                    }
                }
            }
        }

        let totalScore = max(0.001, scores.values.reduce(0, +))
        return scores
            .map { type, score in
                PsychologicalNeedScore(
                    type: type,
                    score: score,
                    ratio: score / totalScore,
                    matchedKeywords: Array(matchedMap[type] ?? []).sorted()
                )
            }
            .filter { $0.score > 0 }
            .sorted { lhs, rhs in
                if lhs.score != rhs.score { return lhs.score > rhs.score }
                return lhs.type.rawValue < rhs.type.rawValue
            }
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
        averageDuration: TimeInterval,
        peakHour: Int?,
        maxPeakDecibels: Float?,
        volumeBreakdown: SleepTalkAnalysis.VolumeBreakdown,
        topKeywords: [SleepTalkAnalysis.KeywordCount],
        primaryNeed: PsychologicalNeedScore?
    ) -> [String] {
        var result: [String] = []

        if let primaryNeed {
            result.append("深層心理では「\(primaryNeed.type.rawValue)」が最も強く表れています。")
        }

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
