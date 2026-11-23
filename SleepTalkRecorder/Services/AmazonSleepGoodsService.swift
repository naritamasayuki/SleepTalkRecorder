import Foundation

/// おすすめ安眠グッズ1件を表すモデル
struct SleepGoodRecommendation: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let searchKeywordJa: String
    let searchKeywordEn: String
}

/// Amazonアソシエイト（物販アフィリエイト）の安全な商品検索URLとおすすめ安眠グッズを提供するサービス
enum AmazonSleepGoodsService {
    /// 日本（Amazon.co.jp）向け共通 Amazon アソシエイト ID
    static let associateTagJP = "shirokumacamp-22"

    /// 指定されたロケールに応じて安全な Amazon 商品検索 URL を生成する
    static func searchURL(for item: SleepGoodRecommendation, locale: Locale = .current) -> URL? {
        let isJapan = locale.region?.identifier == "JP" || locale.language.languageCode?.identifier == "ja"

        var components = URLComponents()
        components.scheme = "https"
        if isJapan {
            components.host = "www.amazon.co.jp"
            components.path = "/s"
            components.queryItems = [
                URLQueryItem(name: "k", value: item.searchKeywordJa),
                URLQueryItem(name: "tag", value: associateTagJP)
            ]
        } else {
            components.host = "www.amazon.com"
            components.path = "/s"
            components.queryItems = [
                URLQueryItem(name: "k", value: item.searchKeywordEn)
            ]
        }
        return components.url
    }

    /// 深層心理の要求タイプに応じたおすすめ安眠グッズを返す
    static func recommendations(for need: PsychologicalNeedType?) -> [SleepGoodRecommendation] {
        switch need {
        case .rest:
            return [hotEyeMask, ergonomicPillow, bathSalt]
        case .relief:
            return [aromaDiffuser, sleepEarplugs, herbalTea]
        case .connection:
            return [bodyPillow, sleepSpeaker, hotEyeMask]
        case .safety:
            return [blackoutEyeMask, warmNightLight, weightedBlanket]
        case .freedom, .clarity, .none:
            return [hotEyeMask, ergonomicPillow, sleepEarplugs]
        }
    }

    // MARK: - グッズ定義

    private static var hotEyeMask: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "hot_eye_mask",
            title: String(localized: "Warming Eye Mask"),
            subtitle: String(localized: "Gently warms tired eyes for deeper sleep"),
            symbolName: "eyeglasses",
            searchKeywordJa: "ホットアイマスク 安眠",
            searchKeywordEn: "heated eye mask for sleeping"
        )
    }

    private static var ergonomicPillow: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "ergonomic_pillow",
            title: String(localized: "Ergonomic Sleep Pillow"),
            subtitle: String(localized: "Supports neck alignment and reduces restlessness"),
            symbolName: "bed.double.fill",
            searchKeywordJa: "安眠枕 低反発",
            searchKeywordEn: "ergonomic memory foam sleep pillow"
        )
    }

    private static var bathSalt: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "bath_salt",
            title: String(localized: "Relaxing Bath Salts"),
            subtitle: String(localized: "Warm up before bed to ease physical fatigue"),
            symbolName: "drop.fill",
            searchKeywordJa: "快眠 入浴剤 リラックス",
            searchKeywordEn: "relaxing lavender bath salts sleep"
        )
    }

    private static var aromaDiffuser: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "aroma_diffuser",
            title: String(localized: "Sleep Aroma Diffuser"),
            subtitle: String(localized: "Lavender & calming scents to release tension"),
            symbolName: "wind",
            searchKeywordJa: "アロマディフューザー ラベンダー 安眠",
            searchKeywordEn: "lavender essential oil diffuser sleep"
        )
    }

    private static var sleepEarplugs: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "sleep_earplugs",
            title: String(localized: "Soft Sleep Earplugs"),
            subtitle: String(localized: "Blocks ambient noise for uninterrupted rest"),
            symbolName: "ear.fill",
            searchKeywordJa: "睡眠用 耳栓 遮音",
            searchKeywordEn: "soft silicone earplugs for sleeping"
        )
    }

    private static var herbalTea: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "herbal_tea",
            title: String(localized: "Caffeine-Free Herbal Tea"),
            subtitle: String(localized: "Chamomile blend to unwind before bedtime"),
            symbolName: "cup.and.saucer.fill",
            searchKeywordJa: "カモミールティー ノンカフェイン 安眠",
            searchKeywordEn: "chamomile bedtime herbal tea caffeine free"
        )
    }

    private static var bodyPillow: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "body_pillow",
            title: String(localized: "Comfort Body Pillow"),
            subtitle: String(localized: "Provides a cozy, reassuring sleeping posture"),
            symbolName: "heart.fill",
            searchKeywordJa: "抱き枕 安眠 ふわふわ",
            searchKeywordEn: "soft full body pillow for sleeping"
        )
    }

    private static var sleepSpeaker: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "sleep_speaker",
            title: String(localized: "White Noise Sound Machine"),
            subtitle: String(localized: "Gentle ambient sounds for peaceful nights"),
            symbolName: "speaker.wave.2.fill",
            searchKeywordJa: "ホワイトノイズマシン 快眠",
            searchKeywordEn: "white noise sound machine for sleeping"
        )
    }

    private static var blackoutEyeMask: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "blackout_eye_mask",
            title: String(localized: "3D Blackout Sleep Mask"),
            subtitle: String(localized: "Blocks light completely for calm, secure rest"),
            symbolName: "moon.fill",
            searchKeywordJa: "遮光 アイマスク 立体 安眠",
            searchKeywordEn: "3d blackout sleep eye mask"
        )
    }

    private static var warmNightLight: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "warm_night_light",
            title: String(localized: "Warm Bedside Night Light"),
            subtitle: String(localized: "Soft amber glow that won't disrupt sleep"),
            symbolName: "lamp.table.fill",
            searchKeywordJa: "ナイトライト 暖色 授乳 ベッドサイド",
            searchKeywordEn: "warm amber bedside night light"
        )
    }

    private static var weightedBlanket: SleepGoodRecommendation {
        SleepGoodRecommendation(
            id: "weighted_blanket",
            title: String(localized: "Weighted Blanket"),
            subtitle: String(localized: "Gentle pressure for a grounded, calm feeling"),
            symbolName: "shield.lefthalf.filled",
            searchKeywordJa: "加重ブランケット 安眠",
            searchKeywordEn: "weighted blanket for anxiety sleep"
        )
    }
}
