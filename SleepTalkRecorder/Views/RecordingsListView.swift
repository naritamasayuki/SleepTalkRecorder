import StoreKit
import SwiftUI

/// 録音された寝言クリップの日付別一覧・お気に入り・再生・削除・共有を行う画面
struct RecordingsListView: View {
    @Environment(\.requestReview) private var requestReview

    @Bindable var store: RecordingStore
    @Bindable var playbackManager: AudioPlaybackManager
    var isMonitoring: Bool

    @State private var showFavoritesOnly = false
    @State private var showDeleteAllConfirm = false
    @State private var showDeleteNonFavoritesConfirm = false

    private var filteredRecordings: [RecordingItem] {
        showFavoritesOnly ? store.recordings.filter(\.isFavorite) : store.recordings
    }

    private var groupedSections: [(day: Date, items: [RecordingItem])] {
        RecordingStore.groupedByDay(filteredRecordings)
    }

    var body: some View {
        NavigationStack {
            Group {
                if store.recordings.isEmpty {
                    ContentUnavailableView(
                        "No Recordings Yet",
                        systemImage: "waveform.slash",
                        description: Text("Start the Sleep Monitor to automatically save detected sleep talk here.")
                    )
                } else {
                    VStack(spacing: 0) {
                        Picker("Filter", selection: $showFavoritesOnly) {
                            Text("All").tag(false)
                            Text("Favorites").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal)
                        .padding(.vertical, 8)

                        if filteredRecordings.isEmpty {
                            ContentUnavailableView(
                                "No Favorite Recordings",
                                systemImage: "star.slash",
                                description: Text("Tap the star icon on any clip to keep your favorite sleep talk here.")
                            )
                        } else {
                            List {
                                if isMonitoring {
                                    Section {
                                        Label(
                                            "Playback is disabled while monitoring. Stop monitoring to play recordings.",
                                            systemImage: "info.circle"
                                        )
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                    }
                                }

                                ForEach(groupedSections, id: \.day) { section in
                                    Section(sectionHeaderTitle(for: section.day)) {
                                        ForEach(section.items) { item in
                                            recordingRow(for: item)
                                        }
                                        .onDelete { offsets in
                                            for index in offsets where section.items.indices.contains(index) {
                                                let target = section.items[index]
                                                if playbackManager.currentPlayingID == target.id {
                                                    playbackManager.stop()
                                                }
                                                store.delete(target)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recordings (\(store.recordings.count))")
            .onAppear {
                store.markAllAsRead()
            }
            .toolbar {
                if !store.recordings.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            if store.recordings.contains(where: \.isFavorite) {
                                Button(role: .destructive) {
                                    showDeleteNonFavoritesConfirm = true
                                } label: {
                                    Label("Delete Non-Favorites", systemImage: "star.slash")
                                }
                            }
                            Button(role: .destructive) {
                                showDeleteAllConfirm = true
                            } label: {
                                Label("Delete All", systemImage: "trash")
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                                .accessibilityLabel(Text("More Options"))
                        }
                    }
                }
            }
            .confirmationDialog(
                "Delete all non-favorite recordings?",
                isPresented: $showDeleteNonFavoritesConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete Non-Favorites", role: .destructive) {
                    if let currentID = playbackManager.currentPlayingID,
                       let current = store.recordings.first(where: { $0.id == currentID }),
                       !current.isFavorite {
                        playbackManager.stop()
                    }
                    store.deleteNonFavorites()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Favorite clips will be kept.")
            }
            .confirmationDialog(
                "Delete all recordings?",
                isPresented: $showDeleteAllConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    playbackManager.stop()
                    store.deleteAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This action cannot be undone.")
            }
            .alert(
                "Playback Error",
                isPresented: Binding(
                    get: { playbackManager.errorMessage != nil },
                    set: { if !$0 { playbackManager.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(playbackManager.errorMessage ?? "")
            }
            .alert(
                "Storage Notice",
                isPresented: Binding(
                    get: { store.lastErrorMessage != nil },
                    set: { if !$0 { store.lastErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.lastErrorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private func recordingRow(for item: RecordingItem) -> some View {
        let isSelected = playbackManager.currentPlayingID == item.id
        let isPlayingThis = isSelected && playbackManager.isPlaying
        let fileURL = store.fileURL(for: item)
        let hasTranscript = !(item.transcript?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    let wasPlaying = isPlayingThis
                    playbackManager.togglePlayback(for: item, fileURL: fileURL)
                    // 録音を実際に再生したタイミングで自然なレビュー依頼条件をチェックする
                    if !wasPlaying, ReviewPromptManager.shouldRequestReview(totalRecordingsCount: store.recordings.count) {
                        ReviewPromptManager.markPromptShown()
                        requestReview()
                    }
                } label: {
                    Image(systemName: isPlayingThis ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(isMonitoring ? .gray : .indigo)
                }
                .buttonStyle(.plain)
                .disabled(isMonitoring)
                .accessibilityLabel(Text(isPlayingThis ? "Pause" : "Play"))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    // 文字起こしがある場合は重複するファイル名表示を省き、すっきり表示する
                    if !hasTranscript {
                        Text(item.fileName)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 12) {
                        Label(item.formattedTimeOnly, systemImage: "clock.badge")
                        Label(item.formattedDuration, systemImage: "timer")
                        Label(String(format: "%.0f dB", item.peakDecibels), systemImage: "speaker.wave.2")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.toggleFavorite(for: item.id)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.body)
                        .foregroundStyle(item.isFavorite ? .yellow : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(item.isFavorite ? "Remove from Favorites" : "Add to Favorites"))

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    ShareLink(item: fileURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Share Audio Clip"))
                }
            }

            if isSelected && playbackManager.duration > 0 {
                VStack(spacing: 4) {
                    Slider(
                        value: Binding(
                            get: { playbackManager.currentTime },
                            set: { playbackManager.seek(to: $0) }
                        ),
                        in: 0...playbackManager.duration
                    )
                    .tint(.indigo)

                    HStack {
                        Text(formatTime(playbackManager.currentTime))
                        Spacer()
                        Text(formatTime(playbackManager.duration))
                    }
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func sectionHeaderTitle(for day: Date) -> String {
        if Calendar.current.isDateInToday(day) {
            return String(localized: "Today")
        }
        if Calendar.current.isDateInYesterday(day) {
            return String(localized: "Yesterday")
        }
        return day.formatted(date: .abbreviated, time: .omitted)
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
