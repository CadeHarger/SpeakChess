import Foundation
import ChessKit

/// Converts a raw speech-recognition transcription into a legal chess move.
///
/// Strategy: exact / alias matching
/// 1. Normalise the transcription (expand homophones, strip noise words).
/// 2. Enumerate every legal move in the current position for the player.
/// 3. For each legal move, generate a set of natural spoken representations and
///    normalise each one identically.
/// 4. Accept the first move whose normalised form exactly equals the normalised
///    transcription — no fuzzy scoring, no threshold.
///
/// Exact matching prevents "pawn takes d6" from ever matching a plain pawn push
/// to d6: the push form "pawn d six" ≠ "pawn takes d six".
enum VoiceMoveParser {

    // MARK: - Public result type

    struct ParsedMove {
        let start: Square
        let end: Square
        let promotionKind: Piece.Kind?   // non-nil for pawn promotions
    }

    // MARK: - Entry point

    static func parse(
        transcription: String,
        board: Board,
        playerColor: Piece.Color
    ) -> ParsedMove? {
        let normalized = normalize(transcription)
        guard !normalized.isEmpty else { return nil }

        let playerPieces = board.position.pieces.filter { $0.color == playerColor }

        for piece in playerPieces {
            let destinations = board.legalMoves(forPieceAt: piece.square)
            for dest in destinations {
                let isCapture = board.position.piece(at: dest) != nil ||
                    (piece.kind == .pawn && dest.file.rawValue != piece.square.file.rawValue)
                let isPawnPromotion = piece.kind == .pawn &&
                    ((playerColor == .white && dest.rank.value == 8) ||
                     (playerColor == .black && dest.rank.value == 1))

                if isPawnPromotion {
                    for kind in Piece.Kind.promotionKinds {
                        let forms = spokenForms(piece: piece, dest: dest,
                                                isCapture: isCapture, promotionKind: kind)
                        if forms.contains(where: { normalize($0) == normalized }) {
                            return ParsedMove(start: piece.square, end: dest, promotionKind: kind)
                        }
                    }
                } else {
                    let forms = spokenForms(piece: piece, dest: dest,
                                            isCapture: isCapture, promotionKind: nil)
                    if forms.contains(where: { normalize($0) == normalized }) {
                        return ParsedMove(start: piece.square, end: dest, promotionKind: nil)
                    }
                }
            }
        }

        return nil
    }

    /// Returns the chess square named in a blindfold-mode query such as
    /// "what piece is on e4" or "which piece is at dee five".
    ///
    /// Pass in the result of `normalize(_:)` so that file homophones
    /// (`"see"` → `"c"`, `"dee"` → `"d"`) and rank homophones
    /// (`"ate"` → `"eight"`) are already resolved before matching.
    ///
    /// Returns `nil` when the text doesn't look like a square query.
    static func parseSquareQuery(_ normalizedText: String) -> Square? {
        let words = normalizedText.split(separator: " ").map(String.init)

        // Require a query trigger word — "what", "what's", "whats", or "which"
        let hasQueryWord = words.contains(where: {
            $0 == "what" || $0 == "which" || $0 == "what's" || $0 == "whats"
        })
        guard hasQueryWord else { return nil }

        let validFiles: Set<String> = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let rankMap: [String: Int] = [
            "one": 1, "two": 2, "three": 3, "four": 4,
            "five": 5, "six": 6, "seven": 7, "eight": 8,
        ]

        // Scan for an adjacent file-letter + rank-word pair
        for i in 0..<(words.count - 1) {
            if validFiles.contains(words[i]), let rankVal = rankMap[words[i + 1]] {
                return Square("\(words[i])\(rankVal)")
            }
        }
        return nil
    }

    // MARK: - Spoken form generation

    /// Generates all reasonable spoken representations for a given move.
    private static func spokenForms(
        piece: Piece,
        dest: Square,
        isCapture: Bool,
        promotionKind: Piece.Kind?
    ) -> [String] {
        let destStr = spokenSquare(dest)
        let srcStr  = spokenSquare(piece.square)
        let takeVerbs = ["takes", "captures", "x"]
        var forms: [String] = []

        switch piece.kind {

        case .pawn:
            if let pk = promotionKind {
                // Promotion forms
                let pkName = pk.spokenName
                forms += [
                    "\(destStr) \(pkName)",
                    "pawn \(destStr) \(pkName)",
                    "\(destStr) promote \(pkName)",
                    "\(destStr) promotes to \(pkName)",
                    "\(destStr) promote to \(pkName)",
                    "promote \(pkName)",
                    "promote to \(pkName)",
                ]
                if isCapture {
                    let fileLetter = piece.square.file.rawValue
                    forms += [
                        "\(fileLetter) takes \(destStr) \(pkName)",
                        "\(fileLetter) captures \(destStr) \(pkName)",
                    ]
                }
            } else if isCapture {
                let fileLetter = piece.square.file.rawValue
                for v in takeVerbs {
                    forms += [
                        "\(fileLetter) \(v) \(destStr)",          // "c takes d five"
                        "pawn \(v) \(destStr)",                   // "pawn takes d five"
                        "pawn \(srcStr) \(v) \(destStr)",         // "pawn c four takes d five"
                    ]
                }
            } else {
                forms += [
                    destStr,
                    "pawn \(destStr)",
                    "pawn to \(destStr)",
                    "\(srcStr) to \(destStr)",
                    "\(srcStr) \(destStr)",
                ]
            }

        case .knight:
            let names = ["knight", "night"]
            for name in names {
                if isCapture {
                    for v in takeVerbs {
                        forms += [
                            "\(name) \(v) \(destStr)",
                            "\(name) \(srcStr) \(v) \(destStr)",
                        ]
                    }
                } else {
                    forms += [
                        "\(name) \(destStr)",
                        "\(name) to \(destStr)",
                        "\(name) \(srcStr) \(destStr)",
                        "\(name) from \(srcStr) to \(destStr)",
                        "\(name) \(srcStr) to \(destStr)",
                    ]
                }
            }

        case .bishop:
            let names = ["bishop"]
            for name in names {
                if isCapture {
                    for v in takeVerbs {
                        forms += ["\(name) \(v) \(destStr)", "\(name) \(srcStr) \(v) \(destStr)"]
                    }
                } else {
                    forms += ["\(name) \(destStr)", "\(name) to \(destStr)",
                              "\(name) \(srcStr) to \(destStr)", "\(name) \(srcStr) \(destStr)"]
                }
            }

        case .rook:
            if isCapture {
                for v in takeVerbs { forms += ["rook \(v) \(destStr)", "rook \(srcStr) \(v) \(destStr)"] }
            } else {
                forms += ["rook \(destStr)", "rook to \(destStr)",
                          "rook \(srcStr) to \(destStr)", "rook \(srcStr) \(destStr)"]
            }

        case .queen:
            if isCapture {
                for v in takeVerbs { forms += ["queen \(v) \(destStr)", "queen \(srcStr) \(v) \(destStr)"] }
            } else {
                forms += ["queen \(destStr)", "queen to \(destStr)",
                          "queen \(srcStr) to \(destStr)", "queen \(srcStr) \(destStr)"]
            }

        case .king:
            // Castling
            let isWhite = (piece.color == .white)
            let kingSrc: Square = isWhite ? .e1 : .e8
            let kingsideDest: Square = isWhite ? .g1 : .g8
            let queensideDest: Square = isWhite ? .c1 : .c8

            if piece.square == kingSrc {
                if dest == kingsideDest {
                    forms += ["castle kingside", "castles kingside", "castle king side",
                              "short castle", "castle short", "o o", "kingside", "castle"]
                } else if dest == queensideDest {
                    forms += ["castle queenside", "castles queenside", "castle queen side",
                              "long castle", "castle long", "o o o", "queenside castle"]
                }
            }

            // Normal king moves
            if isCapture {
                for v in takeVerbs { forms += ["king \(v) \(destStr)"] }
            } else {
                forms += ["king \(destStr)", "king to \(destStr)"]
            }
        }

        return forms.removingDuplicates()
    }

    // MARK: - Normalisation

    /// Lowercases, expands homophones, removes noise words.
    static func normalize(_ text: String) -> String {
        // Apply multi-word phrase substitutions before splitting into tokens so that
        // short phrases mis-recognised by the speech engine map to standard forms.
        var processed = text.lowercased()
        for (pattern, replacement) in phraseSubstitutions {
            processed = processed.replacingOccurrences(of: pattern, with: replacement)
        }

        // Speech recognition often returns fused tokens like "D4", "E5", "F3".
        // Insert a space between a letter and a digit (and vice versa) so the
        // tokeniser sees "d 4" and can canonicalise each side independently.
        let spaced = splitLetterDigit(processed)

        let words = spaced
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .map { canonicalise(word: $0) }
            .filter { !noiseWords.contains($0) }

        return words.joined(separator: " ")
    }

    /// Multi-word phrase substitutions applied before tokenisation.
    /// Useful for whole phrases that the recognizer routinely returns as a unit
    /// and that need to expand to two or more canonical words.
    private static let phraseSubstitutions: [(String, String)] = [
        // "ponte" → pawn takes (common mis-recognition / shorthand)
        ("ponte", "pawn takes"),
        // "rookie" → "rook e" so "rookie one" parses as Re1, "rookie four" as Re4, etc.
        ("rookie", "rook e"),
        // "before" → "b four" so "pawn before" / "before" parses as ...b4
        ("before", "b four"),
        // "detects" → "d takes" (e.g. "detects e five" → d takes e5)
        ("detects", "d takes"),
        // "she takes" → "c takes" (mis-recognition of "c takes")
        ("she takes", "c takes"),
        // "rotate" → "rook takes" (mis-recognition)
        ("rotate", "rook takes"),
    ]

    /// Inserts spaces at letter↔digit boundaries so "pawn d4" → "pawn d 4".
    /// Preserves existing whitespace.
    private static func splitLetterDigit(_ text: String) -> String {
        var out = ""
        var prev: Character? = nil
        for ch in text {
            if let p = prev {
                let pIsLetter = p.isLetter
                let pIsDigit  = p.isNumber
                let cIsLetter = ch.isLetter
                let cIsDigit  = ch.isNumber
                if (pIsLetter && cIsDigit) || (pIsDigit && cIsLetter) {
                    out.append(" ")
                }
            }
            out.append(ch)
            prev = ch
        }
        return out
    }

    private static func canonicalise(word: String) -> String {
        switch word {
        // Ranks — digit forms (emitted by speech recognizer, e.g. "d4")
        case "1":                                return "one"
        case "2":                                return "two"
        case "3":                                return "three"
        case "4":                                return "four"
        case "5":                                return "five"
        case "6":                                return "six"
        case "7":                                return "seven"
        case "8":                                return "eight"
        // Ranks — spoken homophones
        case "one", "won", "wan":                return "one"
        case "two", "too", "tow":                return "two"
        case "three", "free", "tree":            return "three"
        case "four", "for", "fore", "foe":       return "four"
        case "five", "fife", "hive":             return "five"
        case "six", "sicks", "sex":              return "six"
        case "seven":                            return "seven"
        case "eight", "ate", "aight":            return "eight"
        // Files
        case "see", "sea", "si", "cee":          return "c"
        case "bee", "be":                        return "b"
        case "dee", "d.":                        return "d"
        case "ee":                               return "e"
        case "ef", "eff":                        return "f"
        case "gee", "ji":                        return "g"
        case "aitch", "haitch", "age":           return "h"
        // Pieces — pawn aliases (speech recognition mis-hears as household words)
        case "pond", "pone", "pawns",
             "ponds", "pun", "pond's",
             "porn", "paun":                     return "pawn"
        // Pieces — knight aliases
        case "night", "nite", "knit", "ny",
             "nights", "knights":                return "knight"
        // Pieces — rook aliases
        case "rock", "rocks", "rooks":           return "rook"
        // Pieces — bishop/queen/king plurals
        case "bishops":                          return "bishop"
        case "queens":                           return "queen"
        case "kings":                            return "king"
        // Move verbs
        case "capture", "captures", "x",
             "eats", "eat":                      return "takes"
        case "towards":                          return "to"
        // Castling
        case "castles", "castling":              return "castle"
        case "queenside", "queen-side":          return "queenside"
        case "kingside", "king-side":            return "kingside"
        // Promotions
        case "promotes", "promoting":            return "promote"
        // Disambiguation helpers
        case "from", "at":                       return "from"
        // Common mis-recognitions that map to noise words (so they get filtered out)
        case "mood":                             return "move"    // "move" is a noise word
        case "legal":                            return "illegal" // "illegal" is a noise word
        default:                                 return word
        }
    }

    private static let noiseWords: Set<String> = [
        // Articles / filler — NOTE: "a" is intentionally excluded because it is also
        // the chess file letter. Keeping it would strip the "a" from "a3", "a4", etc.
        "the", "an", "my", "i", "let's", "lets", "please",
        "move", "play", "go", "put", "place", "and", "with",
        "now", "ok", "okay", "um", "uh", "er",
        // Prevent TTS echo of "illegal move" from looping: both words filter to ""
        // which then hits the empty-normalized-text guard in GameView and is dropped.
        "illegal",
    ]

    // MARK: - Square → speech

    static func spokenSquare(_ square: Square) -> String {
        "\(square.file.rawValue) \(spokenRank(square.rank.value))"
    }

    static func spokenRank(_ value: Int) -> String {
        switch value {
        case 1: "one"
        case 2: "two"
        case 3: "three"
        case 4: "four"
        case 5: "five"
        case 6: "six"
        case 7: "seven"
        case 8: "eight"
        default: "\(value)"
        }
    }
}

// MARK: - Helpers

extension Piece.Kind {
    var spokenName: String {
        switch self {
        case .king:   "king"
        case .queen:  "queen"
        case .rook:   "rook"
        case .bishop: "bishop"
        case .knight: "knight"
        case .pawn:   "pawn"
        }
    }

    static let promotionKinds: [Piece.Kind] = [.queen, .rook, .bishop, .knight]
}

private extension Array where Element: Hashable {
    func removingDuplicates() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
