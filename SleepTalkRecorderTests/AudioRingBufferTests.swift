import XCTest
@testable import SleepTalkRecorder

final class AudioRingBufferTests: XCTestCase {
    func testAppendAndDrainWithinCapacity() {
        var buffer = AudioRingBuffer<String>(maxFrames: 100)
        buffer.append("chunk1", frameCount: 40)
        buffer.append("chunk2", frameCount: 60)

        XCTAssertEqual(buffer.totalFrames, 100)
        let drained = buffer.drainAll()
        XCTAssertEqual(drained, ["chunk1", "chunk2"])
        XCTAssertEqual(buffer.totalFrames, 0)
        XCTAssertTrue(buffer.drainAll().isEmpty)
    }

    func testOldestChunksEvictedWhenExceedingMaxFrames() {
        var buffer = AudioRingBuffer<String>(maxFrames: 100)
        buffer.append("chunk1", frameCount: 40)
        buffer.append("chunk2", frameCount: 40)
        buffer.append("chunk3", frameCount: 40)

        XCTAssertEqual(buffer.totalFrames, 80)
        XCTAssertEqual(buffer.drainAll(), ["chunk2", "chunk3"])
    }

    func testZeroMaxFramesDropsAllChunks() {
        var buffer = AudioRingBuffer<String>(maxFrames: 0)
        buffer.append("chunk1", frameCount: 40)

        XCTAssertEqual(buffer.totalFrames, 0)
        XCTAssertTrue(buffer.drainAll().isEmpty)
    }

    func testNonPositiveFrameCountIsIgnored() {
        var buffer = AudioRingBuffer<String>(maxFrames: 100)
        buffer.append("invalid", frameCount: 0)
        buffer.append("negative", frameCount: -10)

        XCTAssertEqual(buffer.totalFrames, 0)
        XCTAssertTrue(buffer.drainAll().isEmpty)
    }

    func testClearEmptiesBufferAndResetsTotalFrames() {
        var buffer = AudioRingBuffer<String>(maxFrames: 100)
        buffer.append("chunk1", frameCount: 30)
        buffer.append("chunk2", frameCount: 40)
        buffer.clear()

        XCTAssertEqual(buffer.totalFrames, 0)
        XCTAssertTrue(buffer.drainAll().isEmpty)
    }
}
