import Foundation
import ChessKit

/// Converts a ChessKit `Move` into a natural English phrase for AVSpeechSynthesizer.
/// Uses `Move.checkState` for check/checkmate announcements — no extra board state needed.
enum MoveNarrator {

    // MARK: - Public

    /// Returns a phrase describing the move and any resulting check/checkmate.
    /// Example output: "Knight to f three. Check."
    static func narrate(move: Move) -> String {
        var phrase = describeMove(move)

        switch move.checkState {
        case .checkmate:
            phrase += ". Checkmate."
        case .check:
            phrase += ". Check."
        case .stalemate:
            phrase += ". Stalemate."
        case .none:
            phrase += "."
        }

        return phrase
    }

    // MARK: - Move description

    private static func describeMove(_ move: Move) -> String {
        let destStr = VoiceMoveParser.spokenSquare(move.end)

        // Castling — castling.side is internal; use move.end file to determine direction
        // King ends on g-file for kingside (g1/g8), c-file for queenside (c1/c8)
        if case .castle = move.result {
            return move.end == .g1 || move.end == .g8 ? "Castle kingside" : "Castle queenside"
        }

        // Promotion
        if let promoted = move.promotedPiece {
            let isCapturingPromotion: Bool
            if case .capture = move.result { isCapturingPromotion = true } else { isCapturingPromotion = false }
            let captureWord = isCapturingPromotion ? " takes \(destStr)" : " \(destStr)"
            return "Pawn\(captureWord), promotes to \(promoted.kind.spokenName)"
        }

        // Pawn move
        if move.piece.kind == .pawn {
            if case .capture = move.result {
                let srcFile = move.start.file.rawValue.uppercased()
                return "\(srcFile) takes \(destStr)"
            }
            return destStr.prefix(1).uppercased() + destStr.dropFirst()
        }

        // All other pieces
        let pieceName = move.piece.kind.spokenName.capitalized
        if case .capture = move.result {
            return "\(pieceName) takes \(destStr)"
        }
        return "\(pieceName) to \(destStr)"
    }
}
