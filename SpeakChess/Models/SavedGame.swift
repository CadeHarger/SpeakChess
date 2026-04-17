import Foundation
import SwiftData

/// A completed chess game stored on-device via SwiftData.
/// Moves are stored as an ordered array of SAN strings (e.g. ["e4", "e5", "Nf3"]).
/// All ChessKit types are kept out of this layer to avoid coupling the model to the library.
@Model
final class SavedGame {

    var date: Date
    /// "white" | "black"
    var playerColorRaw: String
    /// "playerWins" | "botWins" | "draw:<reason>"
    var outcomeRaw: String
    var skillLevel: Int
    var moveSANs: [String]

    init(
        date: Date = .now,
        playerColorRaw: String,
        outcomeRaw: String,
        skillLevel: Int,
        moveSANs: [String]
    ) {
        self.date = date
        self.playerColorRaw = playerColorRaw
        self.outcomeRaw = outcomeRaw
        self.skillLevel = skillLevel
        self.moveSANs = moveSANs
    }

    // MARK: - Derived display properties

    var isOngoing: Bool { outcomeRaw == "ongoing" }

    var outcomeDisplay: String {
        switch outcomeRaw {
        case "ongoing":    return "In Progress"
        case "playerWins": return "You won"
        case "botWins":    return "Stockfish won"
        default:
            if outcomeRaw.hasPrefix("draw:") {
                return "Draw — \(outcomeRaw.dropFirst(5))"
            }
            return outcomeRaw
        }
    }

    var outcomeSymbol: String {
        switch outcomeRaw {
        case "ongoing":    return "clock"
        case "playerWins": return "trophy.fill"
        case "botWins":    return "cpu"
        default:           return "equal.circle.fill"
        }
    }

    var playerColorDisplay: String {
        playerColorRaw == "white" ? "White" : "Black"
    }

    var isPlayerWhite: Bool { playerColorRaw == "white" }

    /// Full PGN text for the game, suitable for sharing or importing into other chess apps.
    var pgn: String {
        let result: String
        switch outcomeRaw {
        case "playerWins": result = isPlayerWhite ? "1-0" : "0-1"
        case "botWins":    result = isPlayerWhite ? "0-1" : "1-0"
        default:           result = outcomeRaw.hasPrefix("draw") ? "1/2-1/2" : "*"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy.MM.dd"
        let dateStr = formatter.string(from: date)

        let white = isPlayerWhite ? "Player" : "Stockfish (Level \(skillLevel))"
        let black = isPlayerWhite ? "Stockfish (Level \(skillLevel))" : "Player"

        var header = """
            [Event "SpeakChess"]
            [Date "\(dateStr)"]
            [White "\(white)"]
            [Black "\(black)"]
            [Result "\(result)"]
            """

        // Build move text: "1. e4 e5 2. Nf3 Nc6 …"
        var moveTokens: [String] = []
        for (i, san) in moveSANs.enumerated() {
            if i % 2 == 0 { moveTokens.append("\(i / 2 + 1). \(san)") }
            else           { moveTokens.append(san) }
        }
        let moveText = (moveTokens + [result]).joined(separator: " ")

        return header + "\n\n" + moveText
    }

    /// Formatted relative or absolute date string for list display.
    var formattedDate: String {
        let cal = Calendar.current
        if cal.isDateInToday(date)    { return "Today, \(date.formatted(date: .omitted, time: .shortened))" }
        if cal.isDateInYesterday(date){ return "Yesterday, \(date.formatted(date: .omitted, time: .shortened))" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
