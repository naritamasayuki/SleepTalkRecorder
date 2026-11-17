import Foundation

/// プリロール録音用に直近の音声データチャンクを一定フレーム数まで保持するリングバッファ
struct AudioRingBuffer<Chunk> {
    private struct Entry {
        let chunk: Chunk
        let frameCount: Int
    }

    private var entries: [Entry] = []
    private(set) var totalFrames: Int = 0
    var maxFrames: Int

    /// 最大保持フレーム数を指定して初期化する
    init(maxFrames: Int) {
        self.maxFrames = max(0, maxFrames)
    }

    /// 音声チャンクを末尾に追加し、上限を超えた古いチャンクを先頭から破棄する
    mutating func append(_ chunk: Chunk, frameCount: Int) {
        guard frameCount > 0 else { return }
        guard maxFrames > 0 else {
            entries.removeAll(keepingCapacity: true)
            totalFrames = 0
            return
        }

        entries.append(Entry(chunk: chunk, frameCount: frameCount))
        totalFrames += frameCount

        while totalFrames > maxFrames, !entries.isEmpty {
            let removed = entries.removeFirst()
            totalFrames -= removed.frameCount
        }
    }

    /// 保持している全チャンクを古い順に取り出し、バッファを空にする
    mutating func drainAll() -> [Chunk] {
        let result = entries.map(\.chunk)
        clear()
        return result
    }

    /// バッファの内容をすべて破棄する
    mutating func clear() {
        entries.removeAll(keepingCapacity: true)
        totalFrames = 0
    }
}
