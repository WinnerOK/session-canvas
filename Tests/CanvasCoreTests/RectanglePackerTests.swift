import Foundation
import Testing
@testable import CanvasCore

@Suite struct RectanglePackerTests {
    @Test func sixSquaresPreferACompactBlockOverARibbon() throws {
        let input = Array(repeating: Rect(0, 0, 100, 100), count: 6)
        let packed = try RectanglePacker.pack(input, gap: 0)
        let width = packed.map { $0.x + $0.width }.max()!, height = packed.map { $0.y + $0.height }.max()!
        #expect(width == 300)
        #expect(height == 200)
        #expect(try RectanglePacker.pack(input, gap: 0) == packed)
        verify(packed, gap: 0)
    }

    @Test func unequalRectanglesUseFreeSpacesWithoutRotationAndKeepEqualSizeOrder() throws {
        let input = [Rect(0, 0, 120, 200), Rect(0, 0, 320, 90), Rect(0, 0, 120, 200),
                     Rect(0, 0, 80, 70), Rect(0, 0, 180, 130), Rect(0, 0, 90, 300)]
        let packed = try RectanglePacker.pack(input, gap: 16)
        for (before, after) in zip(input, packed) {
            #expect(before.width == after.width)
            #expect(before.height == after.height)
        }
        #expect(packed[0].y < packed[2].y || (packed[0].y == packed[2].y && packed[0].x < packed[2].x))
        verify(packed, gap: 16)
        #expect(try RectanglePacker.pack(input, gap: 16) == packed)
    }

    @Test func hundredsOfMixedRectanglesRemainCompactAndFinite() throws {
        let input: [Rect] = (0..<250).map { index in
            let width = Double(100 + (index % 7) * 30)
            let height = Double(80 + (index % 11) * 40)
            return Rect(0, 0, width, height)
        }
        let packed = try RectanglePacker.pack(input, gap: 16)
        let width = packed.map { $0.x + $0.width }.max()!, height = packed.map { $0.y + $0.height }.max()!
        #expect(max(width / height, height / width) < 1.3)
        #expect(input.reduce(0) { $0 + $1.width * $1.height } / (width * height) > 0.65)
        verify(packed, gap: 16)
    }

    @Test func emptyAndUnrepresentableBoundsAreHandled() throws {
        #expect(try RectanglePacker.pack([], gap: 16).isEmpty)
        #expect(throws: (any Error).self) { try RectanglePacker.pack([Rect(0, 0, 1e200, 1e200)], gap: 16) }
    }

    private func verify(_ rectangles: [Rect], gap: Double) {
        for (index, rect) in rectangles.enumerated() {
            #expect([rect.x, rect.y, rect.x + rect.width, rect.y + rect.height].allSatisfy { $0.isFinite })
            let padded = Rect(rect.x, rect.y, rect.width + gap, rect.height + gap)
            for other in rectangles.dropFirst(index + 1) {
                #expect(!padded.intersects(Rect(other.x, other.y, other.width + gap, other.height + gap)))
            }
        }
    }
}
