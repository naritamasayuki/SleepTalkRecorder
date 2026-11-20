# App Store Connect 登録用メタデータ & 提出チェックリスト

## 1. 基本情報

- **Bundle ID**: `com.narita.sleeptalkrecorder.4kr684t6kv`（※ 有償 Developer Program 登録時に本番用 ID へ変更推奨）
- **バージョン**: `1.0` (Build `1`)
- **プライマリカテゴリ**: ヘルスケア／フィットネス (Health & Fitness)
- **セカンダリカテゴリ**: ライフスタイル (Lifestyle)
- **年齢制限**: `4+`
- **価格**: 無料

---

## 2. 日本語（ja）メタデータ

- **アプリ名（30文字以内）**:
  `寝言 - 自動録音＆深層心理分析`
- **サブタイトル（30文字以内）**:
  `寝言だけを録音し心のサインを分析`
- **プロモーションテキスト（170文字以内）**:
  `無音はスキップして「寝言だけ」を自動録音。さらに音声を文字起こししてファイル名にし、言葉と声のトーンから深層心理の要求を分析します。`
- **概要（説明文）**:
  ```text
  「寝ている間、自分はどんなことを話しているんだろう？」
  「寝言」は、睡眠中の寝言だけを自動で検知して録音・文字起こし・深層心理分析まで行うシンプルな睡眠サポートアプリです。

  【主な特徴】
  ■ 寝言だけを自動で録音（プリロール機能付き）
  設定した音量しきい値を超えたときだけ自動で録音を開始します。直前1.5秒（設定可）の音声もさかのぼって保存するため、寝言の話し始めが途切れません。無音が続くと自動で停止し、短い物音ノイズは自動除外します。

  ■ 画面ロック（スリープ）中も動作・夜間省電力表示
  おやすみ録音を開始すれば、iPhoneの画面をロックしてもバックグラウンドで監視を継続します。画面の明るさを抑える夜間表示モードも搭載。

  ■ 寝言の内容を自動で音声ファイル名に
  録音された寝言を音声認識で文字起こしし、そのままファイル名に設定します。一覧からすぐに内容を把握でき、共有も簡単です。

  ■ 深層心理の要求＆時間帯分析
  寝言のキーワードと声の大きさ・時間帯から、「休息・回復の要求」「緊張からの解放要求」「承認・つながりの要求」など、無意識の心理サインをグラフとレポートで可視化します。

  ■ プライバシー重視の端末内保存
  録音データはすべてお使いのiPhone内にのみ保存されます。

  ※ 一晩中マイクを待機させるため、充電ケーブルに接続してのご利用をおすすめします。
  ※ 深層心理分析は睡眠中の発話傾向をもとにしたセルフケア向けの参考情報であり、医療診断ではありません。
  ```
- **キーワード（100文字以内）**:
  `寝言,録音,睡眠,いびき,ボイスレコーダー,文字起こし,深層心理,睡眠分析,バックグラウンド録音,寝室`

---

## 3. 英語（en-US）メタデータ

- **App Name (max 30 chars)**:
  `SleepTalk - Auto Recorder`
- **Subtitle (max 30 chars)**:
  `Record & analyze sleep talking`
- **Promotional Text (max 170 chars)**:
  `Skip silence and automatically record only sleep talk. Transcribe clips into filenames and uncover subconscious needs from your nighttime voice.`
- **Description**:
  ```text
  Ever wondered what you say in your sleep?
  SleepTalk automatically detects and records only your sleep talking overnight—no hours of silent audio to scrub through.

  Key Features:
  • Smart Voice-Activated Recording with Pre-Roll
    Recording starts automatically when sound exceeds your threshold, capturing 1.5 seconds of pre-roll audio so the beginning is never cut off. Short background noises are filtered out automatically.
  • Works While Screen Is Locked
    Start Sleep Monitor and lock your iPhone. Background audio monitoring continues overnight, with an optional dimmed Night Mode display.
  • Auto-Transcribe to File Names
    Recorded clips are transcribed using iOS Speech Recognition and automatically named after what you said.
  • Subconscious Needs & Time Analysis
    Explore hourly charts, volume trends, frequent words, and estimated subconscious needs (such as Rest & Recovery or Stress Relief) based on your sleep talk patterns.
  • Private & On-Device
    All recordings and history stay locally on your device.

  Note: Plugging in your charger is recommended for overnight monitoring. Psychological insights are for self-reflection and wellness only, not medical diagnosis.
  ```
- **Keywords (max 100 chars)**:
  `sleep talk,recorder,sleep,snore,voice recorder,transcription,subconscious,dream,night,audio`

---

## 4. App Store 提出前チェックリスト

1. **Apple Developer Program（有償プラン）への加入**:
   - App Store Connect への登録・提出には有償の Apple Developer Program メンバーシップが必要です。
2. **広告バナーの本番対応（重要）**:
   - 現在 [AdBannerView.swift](SleepTalkRecorder/Views/AdBannerView.swift) はプレースホルダー表示になっています。
   - **未実装のダミー広告のまま審査に出すとガイドライン 2.1 でリジェクトされる可能性が高い**ため、提出前に Google Mobile Ads SDK（AdMob）等の実広告を組み込むか、広告未導入時は非表示にするよう変更してください。
3. **プライバシーポリシー URL の公開**:
   - [PRIVACY_POLICY.md](PRIVACY_POLICY.md) の内容を GitHub Pages 等で公開し、App Store Connect の「プライバシーポリシー URL」に設定してください。
4. **スクリーンショットの準備**:
   - iPhone 6.7 / 6.9 インチ用（例: iPhone 17 / 18 Pro Max シミュレータで撮影）のスクリーンショット（モニター画面、録音履歴、深層心理分析画面）を最低 3 枚用意してください。
5. **App Review 情報**:
   - ログイン不要。審査メモ欄に「起動後『Start Sleep Recording / おやすみ録音を開始』をタップし、マイクに向かって発話すると数秒後に録音履歴と分析タブに反映されます」と記載してください。
