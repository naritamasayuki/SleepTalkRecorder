# SleepTalkRecorder（寝言自動録音アプリ）

睡眠中の寝言や物音を自動で検知し、バックグラウンドで録音・保存・再生できる SwiftUI 製 iOS アプリです。

## 主な機能

- **自動音声検知（VOX / VAD）**: マイク入力の音量をリアルタイムで監視し、設定したしきい値（dBFS）を超えたときのみ自動で録音を開始します。
- **プリロール録音（さかのぼり保存）**: リングバッファにより直近の音声（初期設定 1.5 秒）を保持しているため、寝言の話し始めが途切れません。
- **無音自動終了 ＆ ノイズ除外**: 一定時間の無音で自動保存し、設定した最小録音時間未満の単発ノイズは自動で破棄します。
- **バックグラウンド録音対応**: `AVAudioSession`（`playAndRecord`）と `UIBackgroundModes: audio` により、画面ロック中や睡眠中も監視・録音を継続します。
- **夜間省電力表示**: 監視開始時に画面を暗くし、睡眠の妨げにならない低輝度オーバーレイを表示できます。
- **録音履歴の管理・再生**: 録音したクリップ（`.m4a`）の再生、シーク、削除、共有（ShareLink）に対応しています。

## ディレクトリ構成

```text
SleepTalkRecorder/
├── SleepTalkRecorderApp.swift      # エントリーポイント
├── Info.plist                      # マイク権限・バックグラウンドオーディオ設定
├── Models/
│   ├── RecordingItem.swift         # 録音メタデータモデル
│   └── RecorderSettings.swift      # 検知感度・動作設定モデル
├── Services/
│   ├── AudioRingBuffer.swift       # プリロール用リングバッファ
│   ├── VoiceActivityDetector.swift # 音声検知ステートマシン・dBFS計算
│   ├── SleepAudioRecorder.swift    # AVAudioEngineによる自動録音制御
│   ├── AudioPlaybackManager.swift  # AVAudioPlayerによる再生管理
│   └── RecordingStore.swift        # 録音ファイル・JSONメタデータ永続化
└── Views/
    ├── ContentView.swift           # タブナビゲーション
    ├── MonitorView.swift           # おやすみモニター画面
    ├── LevelMeterView.swift        # 音量レベル・しきい値メーター
    ├── RecordingsListView.swift    # 録音履歴一覧・再生画面
    └── SettingsView.swift          # 検知パラメータ設定画面
```

## ビルド・テスト方法

1. `SleepTalkRecorder.xcodeproj` を Xcode で開きます。
2. 実機（マイク録音テスト用）または iOS シミュレータを選択して実行します。
3. コマンドラインからユニットテストを実行する場合:

```bash
xcodebuild test \
  -project SleepTalkRecorder.xcodeproj \
  -scheme SleepTalkRecorder \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```
