import SwiftUI

/// 録音された寝言クリップの一覧・再生・削除・共有を行う画面
struct RecordingsListView: View {
    var store: RecordingStore
    @Bindable var playbackManager: AudioPlaybackManager
    var isMonitoring: Bool

    @State private var showDeleteAllConfirm = false

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

                        Section {
                            ForEach(store.recordings) { item in
                                recordingRow(for: item)
                            }
                            .onDelete { offsets in
                                for index in offsets where store.recordings.indices.contains(index) {
                                    if playbackManager.currentPlayingID == store.recordings[index].id {
                                        playbackManager.stop()
                                    }
                                }
                                store.delete(at: offsets)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Recordings (\(store.recordings.count))")
            .toolbar {
                if !store.recordings.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Delete All", role: .destructive) {
                            showDeleteAllConfirm = true
                        }
                        .foregroundStyle(.red)
                    }
                }
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
        }
    }

    @ViewBuilder
    private func recordingRow(for item: RecordingItem) -> some View {
        let isSelected = playbackManager.currentPlayingID == item.id
        let fileURL = store.fileURL(for: item)

        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    playbackManager.togglePlayback(for: item, fileURL: fileURL)
                } label: {
                    Image(systemName: (isSelected && playbackManager.isPlaying) ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(isMonitoring ? .gray : .indigo)
                }
                .buttonStyle(.plain)
                .disabled(isMonitoring)

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.displayTitle)
                        .font(.headline)
                        .lineLimit(2)

                    Text(item.fileName)
                        .font(.caption2)
                        .foregroundStyle(.cyan.opacity(0.85))
                        .lineLimit(1)

                    HStack(spacing: 12) {
                        if item.transcript != nil {
                            Label(item.formattedDate, systemImage: "calendar")
                        }
                        Label(item.formattedDuration, systemImage: "clock")
                        Label(String(format: "%.0f dB", item.peakDecibels), systemImage: "speaker.wave.2")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if FileManager.default.fileExists(atPath: fileURL.path) {
                    ShareLink(item: fileURL) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
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

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
