import Foundation
import ChessKit

enum GameOutcome: Equatable {
    case ongoing
    case playerWins
    case botWins
    case draw(String)

    /// Raw string for persistence. Returns `nil` for `.ongoing` (incomplete games are not saved).
    var saveString: String? {
        switch self {
        case .ongoing:          return nil
        case .playerWins:       return "playerWins"
        case .botWins:          return "botWins"
        case .draw(let reason): return "draw:\(reason)"
        }
    }
}

@MainActor
final class GameManager: ObservableObject {

    init(playerColor: Piece.Color = .white) {
        self.playerColor = playerColor
    }

    @Published var board = Board()
    @Published var selectedSquare: Square? = nil
    @Published var legalMoveSquares: [Square] = []
    @Published var lastMove: Move? = nil
    @Published var moveHistory: [Move] = []
    @Published var outcome: GameOutcome = .ongoing
    @Published var isWaitingForBot = false
    @Published var pendingPromotion: Move? = nil

    private(set) var playerColor: Piece.Color = .white

    var isGameOver: Bool {
        outcome != .ongoing
    }

    var isPlayerTurn: Bool {
        !isGameOver &&
        !isWaitingForBot &&
        board.position.sideToMove == playerColor &&
        pendingPromotion == nil
    }

    var currentFEN: String {
        board.position.fen
    }

    // MARK: - Captured pieces & material

    struct CapturedPieceCount {
        let pawns: Int
        let knights: Int
        let bishops: Int
        let rooks: Int
        let queens: Int

        static let zero = CapturedPieceCount(pawns: 0, knights: 0, bishops: 0, rooks: 0, queens: 0)

        var materialValue: Int {
            pawns + knights * 3 + bishops * 3 + rooks * 5 + queens * 9
        }

        /// Unicode symbols ordered queen→rook→bishop→knight→pawn, for the given piece colour.
        func symbols(color: Piece.Color) -> [String] {
            let (q, r, b, n, p) = color == .black
                ? ("♛", "♜", "♝", "♞", "♟")
                : ("♕", "♖", "♗", "♘", "♙")
            return Array(repeating: q, count: queens)
                 + Array(repeating: r, count: rooks)
                 + Array(repeating: b, count: bishops)
                 + Array(repeating: n, count: knights)
                 + Array(repeating: p, count: pawns)
        }
    }

    /// Pieces of `color` that have been taken (compared to the 16-piece starting army).
    private func capturedPieces(ofColor color: Piece.Color) -> CapturedPieceCount {
        let onBoard = board.position.pieces.filter { $0.color == color }
        return CapturedPieceCount(
            pawns:   8 - onBoard.filter { $0.kind == .pawn   }.count,
            knights: 2 - onBoard.filter { $0.kind == .knight }.count,
            bishops: 2 - onBoard.filter { $0.kind == .bishop }.count,
            rooks:   2 - onBoard.filter { $0.kind == .rook   }.count,
            queens:  1 - onBoard.filter { $0.kind == .queen  }.count
        )
    }

    /// Opponent pieces captured by the player.
    var capturedByPlayer: CapturedPieceCount { capturedPieces(ofColor: playerColor.opposite) }
    /// Player pieces captured by the opponent.
    var capturedByBot: CapturedPieceCount { capturedPieces(ofColor: playerColor) }

    /// Positive = player is ahead in material; negative = bot is ahead.
    var materialAdvantage: Int { capturedByPlayer.materialValue - capturedByBot.materialValue }

    var statusText: String {
        if pendingPromotion != nil { return "Choose promotion piece" }
        if isWaitingForBot { return "Stockfish is thinking…" }
        switch outcome {
        case .playerWins: return "You win by checkmate!"
        case .botWins:    return "Stockfish wins."
        case .draw(let r): return "Draw — \(r)"
        case .ongoing:
            switch board.state {
            case .check(let color):
                return color == playerColor ? "You are in check!" : "Stockfish is in check"
            default:
                return board.position.sideToMove == playerColor ? "Your turn" : "Stockfish's turn"
            }
        }
    }

    // MARK: - Game setup

    func startNewGame(as color: Piece.Color) {
        playerColor = color
        board = Board()
        selectedSquare = nil
        legalMoveSquares = []
        lastMove = nil
        moveHistory = []
        outcome = .ongoing
        isWaitingForBot = false
        pendingPromotion = nil
    }

    /// Rebuilds game state from a list of SAN strings (e.g. a persisted in-progress game).
    /// `isWaitingForBot` is left `false`; the caller is responsible for triggering the bot
    /// if `board.position.sideToMove != playerColor` after this returns.
    func restoreGame(moveSANs: [String], as color: Piece.Color) {
        playerColor = color
        board = Board()
        selectedSquare = nil
        legalMoveSquares = []
        lastMove = nil
        moveHistory = []
        outcome = .ongoing
        isWaitingForBot = false
        pendingPromotion = nil

        for san in moveSANs {
            guard let move = Move(san: san, position: board.position) else { break }
            _ = board.move(pieceAt: move.start, to: move.end)
            if let promoted = move.promotedPiece, case .promotion(let promMove) = board.state {
                _ = board.completePromotion(of: promMove, to: promoted.kind)
            }
            moveHistory.append(move)
            lastMove = move
        }
    }

    // MARK: - Player input

    func handleSquareTap(_ square: Square) {
        guard isPlayerTurn else { return }

        if let selected = selectedSquare {
            if legalMoveSquares.contains(square) {
                makePlayerMove(from: selected, to: square)
            } else if let piece = board.position.piece(at: square), piece.color == playerColor {
                selectSquare(square)
            } else {
                deselectSquare()
            }
        } else {
            if let piece = board.position.piece(at: square), piece.color == playerColor {
                selectSquare(square)
            }
        }
    }

    func completePlayerPromotion(to kind: Piece.Kind) {
        guard let pending = pendingPromotion else { return }
        pendingPromotion = nil
        let completed = board.completePromotion(of: pending, to: kind)
        replaceLastMove(with: completed)
        handleBoardState()
    }

    func resign() {
        guard !isGameOver else { return }
        outcome = .botWins
    }

    /// Removes the last two half-moves (player move + bot reply) and rebuilds
    /// the board from the remaining SAN history. If fewer than two moves have
    /// been played the call is silently ignored.
    func undoLastTwoMoves() {
        guard moveHistory.count >= 2 else { return }
        let keepCount = moveHistory.count - 2
        let sans = moveHistory.prefix(keepCount).map(\.san)

        board = Board()
        var newHistory: [Move] = []
        var last: Move? = nil

        for san in sans {
            guard let move = Move(san: san, position: board.position) else { break }
            _ = board.move(pieceAt: move.start, to: move.end)
            if let promoted = move.promotedPiece, case .promotion(let pm) = board.state {
                _ = board.completePromotion(of: pm, to: promoted.kind)
            }
            newHistory.append(move)
            last = move
        }

        moveHistory = newHistory
        lastMove = last
        selectedSquare = nil
        legalMoveSquares = []
        isWaitingForBot = false
        pendingPromotion = nil
        outcome = .ongoing
    }

    /// Applies a move from voice input. Auto-completes promotion to `promotionKind` (defaults to queen).
    /// Returns the resulting `Move` so the caller can narrate it, or `nil` if the move was illegal.
    @discardableResult
    func applyVoiceMove(start: Square, end: Square, promotionKind: Piece.Kind?) -> Move? {
        deselectSquare()
        guard let move = board.move(pieceAt: start, to: end) else { return nil }
        moveHistory.append(move)
        lastMove = move

        if case .promotion(let promMove) = board.state {
            let kind = promotionKind ?? .queen
            let completed = board.completePromotion(of: promMove, to: kind)
            replaceLastMove(with: completed)
            lastMove = completed
        }

        handleBoardState()
        return lastMove
    }

    // MARK: - Bot move application

    func applyBotMove(lan: String) {
        isWaitingForBot = false
        guard lan.count >= 4 else { return }

        let start = Square(String(lan.prefix(2)))
        let end   = Square(String(lan.dropFirst(2).prefix(2)))

        guard let move = board.move(pieceAt: start, to: end) else { return }
        moveHistory.append(move)
        lastMove = move

        // Auto-complete bot promotion (engine encodes piece as 5th char, e.g. "e7e8q")
        if case .promotion(let promMove) = board.state {
            var kind: Piece.Kind = .queen
            if lan.count == 5, let last = lan.last {
                kind = Piece.Kind(rawValue: String(last).uppercased()) ?? .queen
            }
            let completed = board.completePromotion(of: promMove, to: kind)
            replaceLastMove(with: completed)
            lastMove = completed
        }

        handleBoardState()
    }

    // MARK: - Private helpers

    private func selectSquare(_ square: Square) {
        selectedSquare = square
        legalMoveSquares = board.legalMoves(forPieceAt: square)
    }

    private func deselectSquare() {
        selectedSquare = nil
        legalMoveSquares = []
    }

    private func makePlayerMove(from start: Square, to end: Square) {
        deselectSquare()
        guard let move = board.move(pieceAt: start, to: end) else { return }
        moveHistory.append(move)
        lastMove = move
        handleBoardState()
    }

    private func replaceLastMove(with move: Move) {
        if !moveHistory.isEmpty {
            moveHistory[moveHistory.count - 1] = move
        }
        lastMove = move
    }

    private func handleBoardState() {
        switch board.state {
        case .active, .check:
            if board.position.sideToMove != playerColor {
                isWaitingForBot = true
            }
        case .checkmate(let loserColor):
            outcome = loserColor == playerColor ? .botWins : .playerWins
        case .draw(let reason):
            outcome = .draw(reason.displayText)
        case .promotion(let promMove):
            // Only player promotions reach here; bot promotions are handled inline in applyBotMove
            pendingPromotion = promMove
        }
    }
}

// MARK: - DrawReason display

private extension Board.State.DrawReason {
    var displayText: String {
        switch self {
        case .agreement:           "agreement"
        case .fiftyMoves:          "fifty-move rule"
        case .insufficientMaterial: "insufficient material"
        case .repetition:          "threefold repetition"
        case .stalemate:           "stalemate"
        }
    }
}
