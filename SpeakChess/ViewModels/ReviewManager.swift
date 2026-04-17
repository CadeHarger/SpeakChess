import Foundation
import ChessKit

/// Manages the board state for move-by-move replay of a saved game.
///
/// Each navigation call (`stepForward`, `stepBack`, `jumpToStart`, `jumpToEnd`)
/// rebuilds the board from the start so Board never needs to be copied.
/// The `@Published` property assignments trigger SwiftUI re-renders automatically.
@MainActor
final class ReviewManager: ObservableObject {

    @Published private(set) var replayBoard: Board = Board()
    @Published private(set) var currentMoveIndex: Int = 0
    @Published private(set) var lastAppliedMove: Move? = nil

    let moveSANs: [String]

    init(moveSANs: [String]) {
        self.moveSANs = moveSANs
    }

    // MARK: - State helpers

    var totalMoves: Int  { moveSANs.count }
    var isAtStart: Bool  { currentMoveIndex == 0 }
    var isAtEnd: Bool    { currentMoveIndex == totalMoves }

    var progressFraction: Double {
        totalMoves == 0 ? 0 : Double(currentMoveIndex) / Double(totalMoves)
    }

    // MARK: - Navigation

    func stepForward() {
        guard !isAtEnd else { return }
        replay(to: currentMoveIndex + 1)
    }

    func stepBack() {
        guard !isAtStart else { return }
        replay(to: currentMoveIndex - 1)
    }

    func jumpToStart() { replay(to: 0) }
    func jumpToEnd()   { replay(to: totalMoves) }

    // MARK: - Core replay engine

    /// Rebuilds the board from scratch to `targetIndex` by applying SAN moves sequentially.
    /// Assigning to `@Published` properties notifies SwiftUI automatically.
    private func replay(to targetIndex: Int) {
        var board = Board()
        var last: Move? = nil
        let target = max(0, min(targetIndex, moveSANs.count))

        for i in 0..<target {
            let san = moveSANs[i]
            guard let move = Move(san: san, position: board.position) else { continue }
            _ = board.move(pieceAt: move.start, to: move.end)
            // Complete any pending promotion using the piece the SAN encoded
            if let promoted = move.promotedPiece, case .promotion(let promMove) = board.state {
                _ = board.completePromotion(of: promMove, to: promoted.kind)
            }
            last = move
        }

        replayBoard = board
        lastAppliedMove = last
        currentMoveIndex = target
    }
}
